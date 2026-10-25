-- =================================================================================
-- 20261021_03_scheduler_repair.sql
-- Forward-Only Scheduler Repair & Deterministic Queue Ordering
-- =================================================================================
-- This migration repairs the scheduler functions deployed in 20260910_scheduler_setup.sql:
-- 1. Adds deterministic ordering: ORDER BY scheduled_time ASC, id ASC LIMIT 50.
-- 2. Protects against starvation and unhandled errors when vault or reminder_events are missing.
-- 3. Safely manages pg_cron registration with idempotency.
-- =================================================================================

-- 1. Create or replace generator invocation function
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
    -- Check if vault schema exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'vault') THEN
        RAISE WARNING 'Supabase Vault extension schema does not exist; skipping reminder generation';
        RETURN;
    END IF;

    -- Retrieve secrets securely from Supabase Vault
    SELECT decrypted_secret INTO v_secret_val FROM vault.decrypted_secrets WHERE name = 'SCHEDULER_SECRET';
    SELECT decrypted_secret INTO v_url_generate FROM vault.decrypted_secrets WHERE name = 'EDGE_FUNCTION_GENERATE_URL';

    IF v_secret_val IS NULL OR v_url_generate IS NULL THEN
        RAISE WARNING 'Missing Vault secrets: SCHEDULER_SECRET or EDGE_FUNCTION_GENERATE_URL';
        RETURN;
    END IF;

    -- Asynchronously invoke the generate-reminders Edge Function if pg_net is available
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

-- 2. Create or replace send invocation function with deterministic ordering
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
    -- Check if vault schema exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'vault') THEN
        RAISE WARNING 'Supabase Vault extension schema does not exist; skipping reminder dispatch';
        RETURN;
    END IF;

    -- Retrieve secrets securely from Supabase Vault
    SELECT decrypted_secret INTO v_secret_val FROM vault.decrypted_secrets WHERE name = 'SCHEDULER_SECRET';
    SELECT decrypted_secret INTO v_url_send FROM vault.decrypted_secrets WHERE name = 'EDGE_FUNCTION_SEND_URL';

    IF v_secret_val IS NULL OR v_url_send IS NULL THEN
        RAISE WARNING 'Missing Vault secrets: SCHEDULER_SECRET or EDGE_FUNCTION_SEND_URL';
        RETURN;
    END IF;

    -- Verify reminder_events table exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'reminder_events') THEN
        RAISE WARNING 'Table public.reminder_events does not exist; skipping reminder dispatch';
        RETURN;
    END IF;

    -- Query eligible pending/expired reminders with strict deterministic ordering
    -- Order by scheduled_time ASC, id ASC to prevent starvation
    -- Limit 50 to prevent unbounded socket queuing
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

-- 3. Idempotently register cron jobs if pg_cron extension is installed
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Unschedule existing if present to avoid duplication
        BEGIN
            PERFORM cron.unschedule('dueit-generate-reminders');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        BEGIN
            PERFORM cron.unschedule('dueit-send-reminders');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        -- Schedule every 5 minutes
        PERFORM cron.schedule('dueit-generate-reminders', '*/5 * * * *', 'SELECT public.dueit_invoke_generate_reminders();');
        PERFORM cron.schedule('dueit-send-reminders', '*/5 * * * *', 'SELECT public.dueit_invoke_send_reminders();');
    ELSE
        RAISE NOTICE 'pg_cron extension not installed; skipping automated cron registration';
    END IF;
END $$;

-- 4. Privilege Hardening
REVOKE ALL ON FUNCTION public.dueit_invoke_generate_reminders() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dueit_invoke_send_reminders() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.dueit_invoke_generate_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.dueit_invoke_send_reminders() TO service_role;
