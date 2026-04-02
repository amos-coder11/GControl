-- Chat grupal único «Mi equipo»: mensajes visibles para todos los usuarios autenticados.

create table if not exists public.team_group_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint team_group_messages_body_len check (char_length(body) between 1 and 8000)
);

create index if not exists team_group_messages_created_idx
  on public.team_group_messages (created_at desc);

alter table public.team_group_messages enable row level security;

create policy "team_group_messages_select_authenticated"
  on public.team_group_messages
  for select
  to authenticated
  using (true);

create policy "team_group_messages_insert_own"
  on public.team_group_messages
  for insert
  to authenticated
  with check (auth.uid() = sender_id);

comment on table public.team_group_messages is
  'Mensajes del grupo interno del equipo (un solo hilo compartido).';

alter publication supabase_realtime add table public.team_group_messages;
