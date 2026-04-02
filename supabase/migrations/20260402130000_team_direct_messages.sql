-- Mensajes directos entre usuarios autenticados (chat interno «Equipo»).
-- La app inserta solo `recipient_id` y `body`; `sender_id` toma `auth.uid()` por defecto.

create table if not exists public.team_direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint team_direct_messages_distinct_users check (sender_id <> recipient_id),
  constraint team_direct_messages_body_len check (char_length(body) between 1 and 8000)
);

create index if not exists team_direct_messages_pair_created_idx
  on public.team_direct_messages (sender_id, recipient_id, created_at desc);

alter table public.team_direct_messages enable row level security;

create policy "team_direct_messages_select_participant"
  on public.team_direct_messages
  for select
  to authenticated
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

create policy "team_direct_messages_insert_own"
  on public.team_direct_messages
  for insert
  to authenticated
  with check (auth.uid() = sender_id and sender_id <> recipient_id);

create policy "team_direct_messages_update_recipient_read"
  on public.team_direct_messages
  for update
  to authenticated
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

comment on table public.team_direct_messages is
  'DM internos: read_at indica que el destinatario ha leído el mensaje.';

-- Marca como leídos los mensajes recibidos desde `p_peer` (abrir conversación).
create or replace function public.mark_team_direct_thread_read(p_peer uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.team_direct_messages
  set read_at = now()
  where recipient_id = auth.uid()
    and sender_id = p_peer
    and read_at is null;
end;
$$;

grant execute on function public.mark_team_direct_thread_read(uuid) to authenticated;

alter publication supabase_realtime add table public.team_direct_messages;
