-- 20261104_01_harden_rls_policies.sql
-- Harden core tables with explicit WITH CHECK clauses to prevent cross-user ID forgery

DROP POLICY IF EXISTS "Users can manage their own tasks" ON public.tasks;
CREATE POLICY "Users can manage their own tasks" ON public.tasks
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their own notes" ON public.notes;
CREATE POLICY "Users can manage their own notes" ON public.notes
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their own streak tasks" ON public.streak_tasks;
CREATE POLICY "Users can manage their own streak tasks" ON public.streak_tasks
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their own dues" ON public.dues;
CREATE POLICY "Users can manage their own dues" ON public.dues
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their own personal expenses" ON public.personal_expenses;
CREATE POLICY "Users can manage their own personal expenses" ON public.personal_expenses
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
