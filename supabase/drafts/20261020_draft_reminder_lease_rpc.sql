-- =================================================================================
-- PHASE 1.3 - DRAFT MIGRATION: DEDICATED LEASE FIELDS & CLAIM RPC (FOR REVIEW ONLY)
-- =================================================================================
-- DO NOT APPLY THIS MIGRATION TO PRODUCTION UNTIL APPROVED
--
-- This migration provides:
-- 1. Explicit 'processing' status in reminder_events_status_check
-- 2. Dedicated lease fields: claimed_by (uuid), claim_expires_at (timestamptz)
-- 3. Stored Procedure: claim_reminder_event(p_reminder_id, p_worker_id, p_lease_seconds)
--    with fixed search_path = public, pg_temp and strict atomicity.
-- =================================================================================

-- 1. Update status constraint to include 'processing'
ALTER TABLE public.reminder_events DROP CONSTRAINT IF EXISTS reminder_events_status_check;
ALTER TABLE public.reminder_events ADD CONSTRAINT reminder_events_status_check 
  CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled'));

-- 2. Add dedicated lease columns if not present
ALTER TABLE public.reminder_events 
  ADD COLUMN IF NOT EXISTS claimed_by uuid,
  ADD COLUMN IF NOT EXISTS claim_expires_at timestamp with time zone;

-- Index to optimize scheduler lookups
CREATE INDEX IF NOT EXISTS idx_reminder_events_sched_status 
  ON public.reminder_events (status, scheduled_time) 
  WHERE status IN ('pending', 'processing');

-- 3. Atomic Claim Stored Procedure
CREATE OR REPLACE FUNCTION public.dueit_claim_reminder(
    p_reminder_id uuid,
    p_worker_id uuid,
    p_lease_seconds int DEFAULT 120
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_updated boolean := false;
BEGIN
    UPDATE public.reminder_events
    SET status = 'processing',
        claimed_by = p_worker_id,
        claim_expires_at = now() + (p_lease_seconds || ' seconds')::interval,
        updated_at = now()
    WHERE id = p_reminder_id
      AND (
        status = 'pending'
        OR (status = 'processing' AND (claim_expires_at IS NULL OR claim_expires_at <= now()))
      );

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN (v_updated > 0);
END;
$$;

-- Revoke all, grant execute only to service_role (used by Edge Functions)
REVOKE ALL ON FUNCTION public.dueit_claim_reminder(uuid, uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dueit_claim_reminder(uuid, uuid, int) TO service_role;
