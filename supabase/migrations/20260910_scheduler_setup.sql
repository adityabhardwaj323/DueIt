-- =================================================================================
-- PHASE 2.4B - SUPABASE PG_CRON REMINDER SCHEDULER
-- =================================================================================
-- IMPORTANT: 
-- Ensure the following extensions are enabled in your Supabase Dashboard:
-- 1. pg_cron
-- 2. pg_net
-- 3. vault

-- Vault setup: Store your secrets via Supabase Dashboard -> Vault
-- Name: SCHEDULER_SECRET
-- Name: EDGE_FUNCTION_GENERATE_URL  (e.g., https://<project>.supabase.co/functions/v1/generate-reminders)
-- Name: EDGE_FUNCTION_SEND_URL      (e.g., https://<project>.supabase.co/functions/v1/send-fcm-notification)
-- =================================================================================

-- 1. Create function to trigger reminder generation
CREATE OR REPLACE FUNCTION dueit_invoke_generate_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_secret_val text;
    v_url_generate text;
BEGIN
    -- Retrieve secrets securely from Supabase Vault
    SELECT decrypted_secret INTO v_secret_val FROM vault.decrypted_secrets WHERE name = 'SCHEDULER_SECRET';
    SELECT decrypted_secret INTO v_url_generate FROM vault.decrypted_secrets WHERE name = 'EDGE_FUNCTION_GENERATE_URL';

    IF v_secret_val IS NULL OR v_url_generate IS NULL THEN
        RAISE WARNING 'Missing Vault secrets: SCHEDULER_SECRET or EDGE_FUNCTION_GENERATE_URL';
        RETURN;
    END IF;

    -- Asynchronously invoke the generate-reminders Edge Function
    PERFORM net.http_post(
        url := v_url_generate,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_secret_val
        )
    );
END;
$$;

-- 2. Create function to select pending reminders and trigger delivery
CREATE OR REPLACE FUNCTION dueit_invoke_send_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_secret_val text;
    v_url_send text;
    v_event record;
BEGIN
    -- Retrieve secrets securely from Supabase Vault
    SELECT decrypted_secret INTO v_secret_val FROM vault.decrypted_secrets WHERE name = 'SCHEDULER_SECRET';
    SELECT decrypted_secret INTO v_url_send FROM vault.decrypted_secrets WHERE name = 'EDGE_FUNCTION_SEND_URL';

    IF v_secret_val IS NULL OR v_url_send IS NULL THEN
        RAISE WARNING 'Missing Vault secrets: SCHEDULER_SECRET or EDGE_FUNCTION_SEND_URL';
        RETURN;
    END IF;

    -- Query pending reminders where scheduled_time <= now() (absolute timestamptz comparison)
    -- Batch limit: 100 to prevent unbounded pg_net queuing
    FOR v_event IN 
        SELECT id FROM reminder_events 
        WHERE status = 'pending' 
          AND scheduled_time <= now() 
          AND scheduled_time IS NOT NULL
        LIMIT 100
    LOOP
        -- Asynchronously invoke the send-fcm-notification Edge Function per eligible reminder
        PERFORM net.http_post(
            url := v_url_send,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || v_secret_val
            ),
            body := jsonb_build_object('reminder_event_id', v_event.id)
        );
    END LOOP;
END;
$$;

-- 3. Schedule the pg_cron jobs (every 5 minutes)
-- First, attempt to unschedule in case they already exist to avoid duplicates
DO $$
BEGIN
    PERFORM cron.unschedule('dueit-generate-reminders');
EXCEPTION WHEN OTHERS THEN
    -- Ignore error if it doesn't exist yet
END;
$$;

DO $$
BEGIN
    PERFORM cron.unschedule('dueit-send-reminders');
EXCEPTION WHEN OTHERS THEN
    -- Ignore error if it doesn't exist yet
END;
$$;

-- Schedule jobs
SELECT cron.schedule('dueit-generate-reminders', '*/5 * * * *', 'SELECT dueit_invoke_generate_reminders();');
SELECT cron.schedule('dueit-send-reminders', '*/5 * * * *', 'SELECT dueit_invoke_send_reminders();');
