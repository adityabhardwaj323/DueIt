create table if not exists public.habit_completions (
  habit_id uuid references public.streak_tasks(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  completed_date date not null,
  created_at timestamptz not null default now(),
  primary key (habit_id, completed_date)
);

alter table public.habit_completions enable row level security;
drop policy if exists "Users can manage their own habit completions"
  on public.habit_completions;
create policy "Users can manage their own habit completions"
  on public.habit_completions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists idx_habit_completions_user_date
  on public.habit_completions (user_id, completed_date);

insert into public.habit_completions (habit_id, user_id, completed_date)
select id, user_id, last_completed_date
from public.streak_tasks
where last_completed_date is not null
on conflict (habit_id, completed_date) do nothing;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'habit_completions'
     ) then
    execute 'alter publication supabase_realtime add table public.habit_completions';
  end if;
end
$$;
