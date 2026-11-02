alter table public.notes
  add column if not exists note_type text not null default 'text'
    check (note_type in ('text', 'checklist')),
  add column if not exists checklist_items jsonb not null default '[]'::jsonb;
