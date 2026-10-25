-- =================================================================================
-- 20261021_01_reminder_schema_baseline.sql
-- Codified Baseline: user_fcm_tokens & reminder_events
-- =================================================================================

-- 1. User FCM Tokens Table
CREATE TABLE IF NOT EXISTS public.user_fcm_tokens (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    fcm_token text NOT NULL UNIQUE,
    device_id text,
    platform text,
    updated_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);

ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own tokens" ON public.user_fcm_tokens;
CREATE POLICY "Users can manage their own tokens" ON public.user_fcm_tokens 
  FOR ALL USING (auth.uid() = user_id);

-- 2. Reminder Events Table
CREATE TABLE IF NOT EXISTS public.reminder_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL,
    due_id uuid REFERENCES public.dues(id) ON DELETE SET NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    entity_type text NOT NULL CHECK (entity_type IN ('task', 'due')),
    entity_title text,
    reminder_type text NOT NULL CHECK (reminder_type IN ('upcoming', 'deadline', 'overdue')),
    scheduled_time timestamptz NOT NULL,
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
    error_message text,
    attempt_count int DEFAULT 0 NOT NULL,
    claim_token uuid,
    claim_expires_at timestamptz,
    sent_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT chk_entity_parentage CHECK (
      (entity_type = 'task' AND (task_id IS NOT NULL OR status IN ('sent', 'failed', 'cancelled'))) OR
      (entity_type = 'due'  AND (due_id IS NOT NULL  OR status IN ('sent', 'failed', 'cancelled')))
    )
);

ALTER TABLE public.reminder_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view their own reminders" ON public.reminder_events;
CREATE POLICY "Users can view their own reminders" ON public.reminder_events 
  FOR SELECT USING (auth.uid() = user_id);

-- 3. Dedicated Indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_reminders_task_unique 
    ON public.reminder_events (task_id, reminder_type, scheduled_time) 
    WHERE task_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_reminders_due_unique 
    ON public.reminder_events (due_id, reminder_type, scheduled_time) 
    WHERE due_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_reminders_sched_status 
    ON public.reminder_events (scheduled_time, id) 
    WHERE status IN ('pending', 'processing');
