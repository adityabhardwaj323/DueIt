alter table public.streak_tasks
  add column if not exists completion_snapshot_date date,
  add column if not exists previous_last_completed_date date,
  add column if not exists previous_current_streak integer,
  add column if not exists previous_best_streak integer;
