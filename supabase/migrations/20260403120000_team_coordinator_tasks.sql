-- Tareas coordinador Viera: visibles por remitente y destinatario; plazo `deadline_at`.

create table if not exists public.team_coordinator_tasks (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  body text not null,
  deadline_at timestamptz not null,
  accepted_at timestamptz,
  step_instructions jsonb not null default '[]'::jsonb,
  reference_image_base64 text,
  created_at timestamptz not null default now(),
  constraint team_coordinator_tasks_distinct_users check (sender_id <> recipient_id),
  constraint team_coordinator_tasks_title_len check (char_length(title) between 1 and 500),
  constraint team_coordinator_tasks_body_len check (char_length(body) between 1 and 12000)
);

create index if not exists team_coordinator_tasks_recipient_deadline_idx
  on public.team_coordinator_tasks (recipient_id, deadline_at asc);

create index if not exists team_coordinator_tasks_sender_created_idx
  on public.team_coordinator_tasks (sender_id, created_at desc);

alter table public.team_coordinator_tasks enable row level security;

create policy "team_coordinator_tasks_select_participant"
  on public.team_coordinator_tasks
  for select
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

create policy "team_coordinator_tasks_insert_sender"
  on public.team_coordinator_tasks
  for insert
  to authenticated
  with check (auth.uid() = sender_id and sender_id <> recipient_id);

create policy "team_coordinator_tasks_update_participant"
  on public.team_coordinator_tasks
  for update
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id)
  with check (auth.uid() = sender_id or auth.uid() = recipient_id);

comment on table public.team_coordinator_tasks is
  'Tareas enviadas a un comercial (Viera); deadline_at editable por el remitente.';

alter publication supabase_realtime add table public.team_coordinator_tasks;
