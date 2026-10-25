-- =================================================================================
-- 20261023_04_production_reconciliation.sql
-- DueIt Forward-Only Production Schema Reconciliation
-- =================================================================================

-- NOTE: Migration history tracking is managed out-of-band via Supabase CLI
-- (e.g. `supabase migration repair --status applied <version>`) after schema execution,
-- to avoid premature recording or conflicting with internal CLI metadata structures.

-- 2. FCM Token Compatibility Reconciliation
-- Live production schema has: token text NOT NULL, UNIQUE(token), UNIQUE(user_id, device_id)
-- Flutter and Edge Functions query and write to: fcm_token
-- This step non-destructively aligns the table without dropping existing tokens:
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'user_fcm_tokens' AND column_name = 'fcm_token'
  ) THEN
    ALTER TABLE public.user_fcm_tokens ADD COLUMN fcm_token text;
    -- Backfill from token if token column exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' AND table_name = 'user_fcm_tokens' AND column_name = 'token'
    ) THEN
      UPDATE public.user_fcm_tokens SET fcm_token = token WHERE fcm_token IS NULL;
    END IF;
  END IF;

  -- Ensure token column also exists if this is applied on a fresh database with fcm_token
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'user_fcm_tokens' AND column_name = 'token'
  ) THEN
    ALTER TABLE public.user_fcm_tokens ADD COLUMN token text;
    UPDATE public.user_fcm_tokens SET token = fcm_token WHERE token IS NULL;
  END IF;
END $$;

-- Synchronize token and fcm_token consistently on writes
CREATE OR REPLACE FUNCTION public.sync_user_fcm_token_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Handle token and fcm_token alignment without silent corruption or conflicting values
  IF NEW.fcm_token IS NOT NULL AND NEW.token IS NULL THEN
    NEW.token := NEW.fcm_token;
  ELSIF NEW.token IS NOT NULL AND NEW.fcm_token IS NULL THEN
    NEW.fcm_token := NEW.token;
  ELSIF NEW.fcm_token IS NOT NULL AND NEW.token IS NOT NULL AND NEW.fcm_token <> NEW.token THEN
    -- If both are supplied with differing values, prioritize fcm_token as canonical for modern clients
    NEW.token := NEW.fcm_token;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_user_fcm_tokens ON public.user_fcm_tokens;
CREATE TRIGGER trg_sync_user_fcm_tokens
  BEFORE INSERT OR UPDATE ON public.user_fcm_tokens
  FOR EACH ROW EXECUTE FUNCTION public.sync_user_fcm_token_columns();

-- Ensure index on fcm_token for fast lookup by sender Edge Function
CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_fcm_token 
  ON public.user_fcm_tokens (fcm_token) 
  WHERE fcm_token IS NOT NULL;

-- 3. Ensure Reminder Events Columns Exist (claim lease support)
ALTER TABLE public.reminder_events 
  ADD COLUMN IF NOT EXISTS claim_token uuid,
  ADD COLUMN IF NOT EXISTS claim_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS attempt_count int DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS error_message text,
  ADD COLUMN IF NOT EXISTS sent_at timestamptz;

-- Ensure optimal sweep index for scheduler
CREATE INDEX IF NOT EXISTS idx_reminders_sched_status 
  ON public.reminder_events (scheduled_time, id) 
  WHERE status IN ('pending', 'processing');

-- Ensure canonical production unique partial indexes exist for idempotent deduplication
CREATE UNIQUE INDEX IF NOT EXISTS unique_active_task_reminder 
  ON public.reminder_events (task_id, reminder_type, scheduled_time) 
  WHERE (task_id IS NOT NULL) AND (status = 'pending');

CREATE UNIQUE INDEX IF NOT EXISTS unique_active_due_reminder 
  ON public.reminder_events (due_id, reminder_type, scheduled_time) 
  WHERE (due_id IS NOT NULL) AND (status = 'pending');


-- 4. Deterministic Helper Functions
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

-- 5. Atomic Occurrence Ingestion RPC
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
      'task'::text AS entity_type, t.title AS entity_title,
      EXISTS (
        SELECT 1 FROM public.reminder_events r
        WHERE r.task_id = s.task_id
          AND r.reminder_type = s.reminder_type
          AND r.scheduled_time = s.scheduled_time
          AND r.status IN ('pending', 'processing', 'sent')
      ) AS already_exists
    FROM structurally_valid s
    JOIN public.tasks t ON t.id = s.task_id AND t.user_id = s.user_id
    WHERE t.is_completed = false
  ),
  verified_dues AS (
    SELECT
      NULL::uuid AS task_id, s.due_id, s.user_id, s.reminder_type, s.scheduled_time,
      'due'::text AS entity_type,
      (d.person_name || ' (' || d.direction || ' ' || d.amount::text || ')') AS entity_title,
      EXISTS (
        SELECT 1 FROM public.reminder_events r
        WHERE r.due_id = s.due_id
          AND r.reminder_type = s.reminder_type
          AND r.scheduled_time = s.scheduled_time
          AND r.status IN ('pending', 'processing', 'sent')
      ) AS already_exists
    FROM structurally_valid s
    JOIN public.dues d ON d.id = s.due_id AND d.user_id = s.user_id
    WHERE d.status <> 'settled'
  ),
  all_verified AS (
    SELECT * FROM verified_tasks
    UNION ALL
    SELECT * FROM verified_dues
  ),
  new_candidates AS (
    SELECT * FROM all_verified WHERE NOT already_exists
  ),
  deduped_payload AS (
    SELECT DISTINCT ON (task_id, due_id, reminder_type, scheduled_time)
      task_id, due_id, user_id, reminder_type, scheduled_time, entity_type, entity_title
    FROM new_candidates
    ORDER BY task_id, due_id, reminder_type, scheduled_time
  ),
  ins_tasks AS (
    INSERT INTO public.reminder_events (
      task_id, user_id, reminder_type, scheduled_time, entity_type, entity_title, status
    )
    SELECT task_id, user_id, reminder_type, scheduled_time, entity_type, entity_title, 'pending'
    FROM deduped_payload
    WHERE entity_type = 'task'
    ON CONFLICT (task_id, reminder_type, scheduled_time) WHERE (task_id IS NOT NULL) AND (status = 'pending') DO NOTHING
    RETURNING id
  ),
  ins_dues AS (
    INSERT INTO public.reminder_events (
      due_id, user_id, reminder_type, scheduled_time, entity_type, entity_title, status
    )
    SELECT due_id, user_id, reminder_type, scheduled_time, entity_type, entity_title, 'pending'
    FROM deduped_payload
    WHERE entity_type = 'due'
    ON CONFLICT (due_id, reminder_type, scheduled_time) WHERE (due_id IS NOT NULL) AND (status = 'pending') DO NOTHING
    RETURNING id
  )
  SELECT
    (SELECT count(*) FROM ins_tasks) + (SELECT count(*) FROM ins_dues),
    v_total - (SELECT count(*) FROM all_verified)
  INTO v_inserted, v_invalid;

  -- Accurate duplicate calculation: everything verified that was not newly inserted is a duplicate
  v_duplicates := v_total - v_inserted - v_invalid;

  RETURN jsonb_build_object(
    'total_submitted', v_total,
    'inserted_count', v_inserted,
    'duplicate_count', v_duplicates,
    'invalid_count', v_invalid
  );
END;
$$;

-- 6. Atomic Claim RPC
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
  -- Mark exhausted expired claims as failed
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

-- 7. Atomic Finalize RPC
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

-- 8. Lifecycle Cancellation Triggers
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

-- 9. Scheduler Invocation Routines (Safely guarded against missing Vault and pg_net)
CREATE OR REPLACE FUNCTION public.dueit_invoke_generate_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_secret_val text;
    v_url_generate text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'vault') THEN
        RAISE WARNING 'Vault extension schema does not exist; skipping reminder generation';
        RETURN;
    END IF;

    SELECT decrypted_secret INTO v_secret_val FROM vault.decrypted_secrets WHERE name = 'SCHEDULER_SECRET';
    SELECT decrypted_secret INTO v_url_generate FROM vault.decrypted_secrets WHERE name = 'EDGE_FUNCTION_GENERATE_URL';

    IF v_secret_val IS NULL OR v_url_generate IS NULL THEN
        RAISE WARNING 'Missing Vault secrets: SCHEDULER_SECRET or EDGE_FUNCTION_GENERATE_URL';
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
        PERFORM net.http_post(
            url := v_url_generate,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || v_secret_val
            )
        );
    ELSE
        RAISE WARNING 'pg_net extension is not installed; skipping HTTP dispatch';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.dueit_invoke_send_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_secret_val text;
    v_url_send text;
    v_event record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'vault') THEN
        RAISE WARNING 'Vault extension schema does not exist; skipping reminder dispatch';
        RETURN;
    END IF;

    SELECT decrypted_secret INTO v_secret_val FROM vault.decrypted_secrets WHERE name = 'SCHEDULER_SECRET';
    SELECT decrypted_secret INTO v_url_send FROM vault.decrypted_secrets WHERE name = 'EDGE_FUNCTION_SEND_URL';

    IF v_secret_val IS NULL OR v_url_send IS NULL THEN
        RAISE WARNING 'Missing Vault secrets: SCHEDULER_SECRET or EDGE_FUNCTION_SEND_URL';
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reminder_events') THEN
        RAISE WARNING 'Table public.reminder_events does not exist; skipping reminder dispatch';
        RETURN;
    END IF;

    FOR v_event IN 
        SELECT id FROM public.reminder_events 
        WHERE (
            status = 'pending'
            OR (status = 'processing' AND claim_expires_at <= now())
        )
        AND scheduled_time <= now()
        AND attempt_count < 3
        ORDER BY scheduled_time ASC, id ASC
        LIMIT 50
    LOOP
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
            PERFORM net.http_post(
                url := v_url_send,
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || v_secret_val
                ),
                body := jsonb_build_object('reminder_event_id', v_event.id)
            );
        END IF;
    END LOOP;
END;
$$;

-- 10. Idempotent pg_cron registration
DO $$
DECLARE
  v_job record;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Unschedules existing DueIt jobs by name if they are present in cron.job.
    -- Does not swallow genuine errors (e.g. permission or table corruption).
    FOR v_job IN
      SELECT jobid, jobname
      FROM cron.job
      WHERE jobname IN ('dueit-generate-reminders', 'dueit-send-reminders')
    LOOP
      PERFORM cron.unschedule(v_job.jobid);
    END LOOP;

    -- Register jobs with deterministic schedules
    PERFORM cron.schedule('dueit-generate-reminders', '*/5 * * * *', 'SELECT public.dueit_invoke_generate_reminders();');
    PERFORM cron.schedule('dueit-send-reminders', '* * * * *', 'SELECT public.dueit_invoke_send_reminders();');
  ELSE
    RAISE NOTICE 'pg_cron extension not installed; skipping automated cron registration';
  END IF;
END $$;

-- 11. Strict Permissions Hardening
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    REVOKE ALL ON FUNCTION public.dueit_try_cast_uuid(text) FROM PUBLIC;
    REVOKE ALL ON FUNCTION public.dueit_try_cast_timestamptz(text) FROM PUBLIC;
    REVOKE ALL ON FUNCTION public.dueit_insert_reminder_occurrences(jsonb) FROM PUBLIC;
    REVOKE ALL ON FUNCTION public.dueit_claim_reminder(uuid, int) FROM PUBLIC;
    REVOKE ALL ON FUNCTION public.dueit_finalize_reminder(uuid, uuid, text, text) FROM PUBLIC;
    REVOKE ALL ON FUNCTION public.dueit_invoke_generate_reminders() FROM PUBLIC;
    REVOKE ALL ON FUNCTION public.dueit_invoke_send_reminders() FROM PUBLIC;

    GRANT EXECUTE ON FUNCTION public.dueit_try_cast_uuid(text) TO service_role;
    GRANT EXECUTE ON FUNCTION public.dueit_try_cast_timestamptz(text) TO service_role;
    GRANT EXECUTE ON FUNCTION public.dueit_insert_reminder_occurrences(jsonb) TO service_role;
    GRANT EXECUTE ON FUNCTION public.dueit_claim_reminder(uuid, int) TO service_role;
    GRANT EXECUTE ON FUNCTION public.dueit_finalize_reminder(uuid, uuid, text, text) TO service_role;
    GRANT EXECUTE ON FUNCTION public.dueit_invoke_generate_reminders() TO service_role;
    GRANT EXECUTE ON FUNCTION public.dueit_invoke_send_reminders() TO service_role;
  END IF;
END $$;

