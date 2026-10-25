-- =================================================================================
-- 20261021_02_reminder_rpc_and_triggers.sql
-- Codified Stored Procedures, Privileges, and Lifecycle Triggers
-- =================================================================================

-- 1. Deterministic Safe-Cast Helpers
CREATE OR REPLACE FUNCTION public.dueit_try_cast_uuid(p_val text)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN p_val::uuid;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.dueit_try_cast_timestamptz(p_val text)
RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN p_val::timestamptz;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

-- 2. Safe Occurrence Ingestion RPC
CREATE OR REPLACE FUNCTION public.dueit_insert_reminder_occurrences(p_reminders jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_total int;
  v_inserted int := 0;
  v_invalid int := 0;
  v_duplicates int := 0;
BEGIN
  IF p_reminders IS NULL OR jsonb_typeof(p_reminders) <> 'array' THEN
    RETURN jsonb_build_object(
      'total_submitted', 0,
      'inserted_count', 0,
      'duplicate_count', 0,
      'invalid_count', 0,
      'error', 'Input must be a JSON array'
    );
  END IF;

  v_total := jsonb_array_length(p_reminders);
  IF v_total = 0 THEN
    RETURN jsonb_build_object(
      'total_submitted', 0,
      'inserted_count', 0,
      'duplicate_count', 0,
      'invalid_count', 0
    );
  END IF;

  WITH parsed_items AS (
    SELECT
      public.dueit_try_cast_uuid(elem->>'task_id') AS task_id,
      public.dueit_try_cast_uuid(elem->>'due_id') AS due_id,
      public.dueit_try_cast_uuid(elem->>'user_id') AS user_id,
      elem->>'reminder_type' AS reminder_type,
      public.dueit_try_cast_timestamptz(elem->>'scheduled_time') AS scheduled_time,
      elem->>'task_id' AS raw_task_id,
      elem->>'due_id' AS raw_due_id
    FROM jsonb_array_elements(p_reminders) AS elem
  ),
  structurally_valid AS (
    SELECT *
    FROM parsed_items
    WHERE user_id IS NOT NULL
      AND scheduled_time IS NOT NULL
      AND reminder_type IN ('upcoming', 'deadline', 'overdue')
      AND (
        (task_id IS NOT NULL AND raw_due_id IS NULL)
        OR
        (due_id IS NOT NULL AND raw_task_id IS NULL)
      )
  ),
  verified_tasks AS (
    SELECT
      s.task_id, NULL::uuid AS due_id, s.user_id, s.reminder_type, s.scheduled_time,
      'task'::text AS entity_type, t.title AS entity_title
    FROM structurally_valid s
    JOIN public.tasks t ON t.id = s.task_id AND t.user_id = s.user_id
    WHERE t.is_completed = false
  ),
  verified_dues AS (
    SELECT
      NULL::uuid AS task_id, s.due_id, s.user_id, s.reminder_type, s.scheduled_time,
      'due'::text AS entity_type,
      (d.person_name || ' (' || d.direction || ' ' || d.amount::text || ')') AS entity_title
    FROM structurally_valid s
    JOIN public.dues d ON d.id = s.due_id AND d.user_id = s.user_id
    WHERE d.status <> 'settled'
  ),
  all_verified AS (
    SELECT * FROM verified_tasks
    UNION ALL
    SELECT * FROM verified_dues
  ),
  deduped_payload AS (
    SELECT DISTINCT ON (task_id, due_id, reminder_type, scheduled_time)
      task_id, due_id, user_id, reminder_type, scheduled_time, entity_type, entity_title
    FROM all_verified
    ORDER BY task_id, due_id, reminder_type, scheduled_time
  ),
  ins_tasks AS (
    INSERT INTO public.reminder_events (
      task_id, user_id, reminder_type, scheduled_time, entity_type, entity_title, status
    )
    SELECT task_id, user_id, reminder_type, scheduled_time, entity_type, entity_title, 'pending'
    FROM deduped_payload
    WHERE entity_type = 'task'
    ON CONFLICT (task_id, reminder_type, scheduled_time) WHERE task_id IS NOT NULL DO NOTHING
    RETURNING id
  ),
  ins_dues AS (
    INSERT INTO public.reminder_events (
      due_id, user_id, reminder_type, scheduled_time, entity_type, entity_title, status
    )
    SELECT due_id, user_id, reminder_type, scheduled_time, entity_type, entity_title, 'pending'
    FROM deduped_payload
    WHERE entity_type = 'due'
    ON CONFLICT (due_id, reminder_type, scheduled_time) WHERE due_id IS NOT NULL DO NOTHING
    RETURNING id
  )
  SELECT
    (SELECT count(*) FROM ins_tasks) + (SELECT count(*) FROM ins_dues),
    v_total - (SELECT count(*) FROM all_verified)
  INTO v_inserted, v_invalid;

  v_duplicates := v_total - v_inserted - v_invalid;

  RETURN jsonb_build_object(
    'total_submitted', v_total,
    'inserted_count', v_inserted,
    'duplicate_count', v_duplicates,
    'invalid_count', v_invalid
  );
END;
$$;

-- 3. Atomic Claim RPC
CREATE OR REPLACE FUNCTION public.dueit_claim_reminder(
  p_reminder_id uuid,
  p_lease_seconds int DEFAULT 120
)
RETURNS TABLE (
  claimed boolean,
  claim_token uuid,
  claim_expires_at timestamptz,
  reminder_record jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token uuid := gen_random_uuid();
  v_clamped_lease int := GREATEST(30, LEAST(COALESCE(p_lease_seconds, 120), 300));
  v_expires timestamptz := now() + (v_clamped_lease || ' seconds')::interval;
  v_row public.reminder_events%ROWTYPE;
BEGIN
  -- Mark exhausted expired claims as failed (fully qualify table name)
  UPDATE public.reminder_events
  SET status = 'failed',
      error_message = 'Max retry attempts exhausted',
      claim_token = NULL,
      claim_expires_at = NULL,
      updated_at = now()
  WHERE reminder_events.id = p_reminder_id
    AND reminder_events.attempt_count >= 3
    AND reminder_events.status = 'processing'
    AND reminder_events.claim_expires_at <= now();

  -- Atomically claim eligible event
  UPDATE public.reminder_events
  SET
    status = 'processing',
    claim_token = v_token,
    claim_expires_at = v_expires,
    attempt_count = reminder_events.attempt_count + 1,
    updated_at = now()
  WHERE reminder_events.id = p_reminder_id
    AND reminder_events.scheduled_time <= now()
    AND reminder_events.attempt_count < 3
    AND (
      reminder_events.status = 'pending' 
      OR (reminder_events.status = 'processing' AND reminder_events.claim_expires_at <= now())
    )
  RETURNING * INTO v_row;

  IF FOUND THEN
    RETURN QUERY SELECT TRUE, v_token, v_expires, to_jsonb(v_row);
  ELSE
    RETURN QUERY SELECT FALSE, NULL::uuid, NULL::timestamptz, NULL::jsonb;
  END IF;
END;
$$;

-- 4. Atomic Finalize RPC
CREATE OR REPLACE FUNCTION public.dueit_finalize_reminder(
  p_reminder_id uuid,
  p_claim_token uuid,
  p_outcome text,
  p_error text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  IF p_outcome NOT IN ('sent', 'cancelled', 'failed', 'retryable') THEN
    RAISE EXCEPTION 'Invalid outcome: %', p_outcome;
  END IF;

  UPDATE public.reminder_events
  SET
    status = CASE 
      WHEN p_outcome = 'retryable' AND attempt_count >= 3 THEN 'failed'
      WHEN p_outcome = 'retryable' THEN 'pending'
      ELSE p_outcome
    END,
    claim_token = NULL,
    claim_expires_at = NULL,
    error_message = CASE 
      WHEN p_outcome = 'retryable' AND attempt_count >= 3 THEN COALESCE(p_error, 'Max retries exhausted')
      ELSE p_error
    END,
    sent_at = CASE WHEN p_outcome = 'sent' THEN now() ELSE sent_at END,
    updated_at = now()
  WHERE id = p_reminder_id
    AND claim_token = p_claim_token
    AND status = 'processing';

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;

-- 5. Lifecycle Cancellation Triggers
CREATE OR REPLACE FUNCTION public.dueit_sync_entity_cancellation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_TABLE_NAME = 'tasks' THEN
    IF TG_OP = 'UPDATE' THEN
      IF (NEW.is_completed = true AND OLD.is_completed = false)
         OR (NEW.due_date IS DISTINCT FROM OLD.due_date) THEN
        UPDATE public.reminder_events
        SET status = 'cancelled', updated_at = now(), claim_token = NULL, claim_expires_at = NULL
        WHERE task_id = OLD.id AND status IN ('pending', 'processing');
      END IF;
    ELSIF TG_OP = 'DELETE' THEN
      UPDATE public.reminder_events
      SET status = 'cancelled', updated_at = now(), claim_token = NULL, claim_expires_at = NULL
      WHERE task_id = OLD.id AND status IN ('pending', 'processing');
    END IF;
  ELSIF TG_TABLE_NAME = 'dues' THEN
    IF TG_OP = 'UPDATE' THEN
      IF (NEW.status = 'settled' AND OLD.status <> 'settled')
         OR (NEW.due_date IS DISTINCT FROM OLD.due_date) THEN
        UPDATE public.reminder_events
        SET status = 'cancelled', updated_at = now(), claim_token = NULL, claim_expires_at = NULL
        WHERE due_id = OLD.id AND status IN ('pending', 'processing');
      END IF;
    ELSIF TG_OP = 'DELETE' THEN
      UPDATE public.reminder_events
      SET status = 'cancelled', updated_at = now(), claim_token = NULL, claim_expires_at = NULL
      WHERE due_id = OLD.id AND status IN ('pending', 'processing');
    END IF;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_dueit_tasks_cancel ON public.tasks;
CREATE TRIGGER trg_dueit_tasks_cancel
  AFTER UPDATE OR DELETE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.dueit_sync_entity_cancellation();

DROP TRIGGER IF EXISTS trg_dueit_dues_cancel ON public.dues;
CREATE TRIGGER trg_dueit_dues_cancel
  AFTER UPDATE OR DELETE ON public.dues
  FOR EACH ROW EXECUTE FUNCTION public.dueit_sync_entity_cancellation();

-- 6. Privilege Hardening
REVOKE ALL ON FUNCTION public.dueit_try_cast_uuid(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dueit_try_cast_timestamptz(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dueit_insert_reminder_occurrences(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dueit_claim_reminder(uuid, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dueit_finalize_reminder(uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.dueit_try_cast_uuid(text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.dueit_try_cast_timestamptz(text) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.dueit_insert_reminder_occurrences(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.dueit_claim_reminder(uuid, int) TO service_role;
GRANT EXECUTE ON FUNCTION public.dueit_finalize_reminder(uuid, uuid, text, text) TO service_role;
