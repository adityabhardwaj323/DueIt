-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- 1. Tasks Table
create table public.tasks (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references auth.users not null,
    title text not null,
    description text,
    due_date timestamp with time zone,
    priority text default 'medium' check (priority in ('low', 'medium', 'high')),
    is_completed boolean default false,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
alter table public.tasks enable row level security;
create policy "Users can manage their own tasks" on public.tasks for all using (auth.uid() = user_id);

-- 2. Notes Table
create table public.notes (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references auth.users not null,
    title text,
    content text not null,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
alter table public.notes enable row level security;
create policy "Users can manage their own notes" on public.notes for all using (auth.uid() = user_id);

-- 3. Streak Tasks Table
create table public.streak_tasks (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references auth.users not null,
    title text not null,
    current_streak integer default 0,
    best_streak integer default 0,
    last_completed_date date,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
alter table public.streak_tasks enable row level security;
create policy "Users can manage their own streak tasks" on public.streak_tasks for all using (auth.uid() = user_id);

-- 4. Dues Table
create table public.dues (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references auth.users not null,
    direction text not null check (direction in ('lent', 'borrowed')),
    person_name text not null,
    person_email text,
    amount numeric not null,
    reason text,
    transaction_date timestamp with time zone default now(),
    due_date timestamp with time zone,
    status text default 'pending' check (status in ('pending', 'settled', 'overdue')),
    is_recurring boolean default false,
    recurrence_interval text,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
alter table public.dues enable row level security;
create policy "Users can manage their own dues" on public.dues for all using (auth.uid() = user_id);

-- 5. Personal Expenses Table
create table public.personal_expenses (
    id uuid default uuid_generate_v4() primary key,
    user_id uuid references auth.users not null,
    amount numeric not null,
    description text not null,
    category text,
    expense_date timestamp with time zone default now(),
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);
alter table public.personal_expenses enable row level security;
create policy "Users can manage their own personal expenses" on public.personal_expenses for all using (auth.uid() = user_id);
