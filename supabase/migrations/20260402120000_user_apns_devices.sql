-- Tokens APNs por usuario (la app iOS hace upsert tras `registerForRemoteNotifications`).
-- Para enviar push con la app cerrada, un backend (p. ej. Edge Function con JWT ES256 y la clave .p8 de Apple)
-- debe leer esta tabla y llamar a la API HTTP/2 de APNs.

create table if not exists public.user_apns_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  device_token text not null,
  updated_at timestamptz not null default now(),
  unique (user_id, device_token)
);

create index if not exists user_apns_devices_user_id_idx on public.user_apns_devices (user_id);

alter table public.user_apns_devices enable row level security;

create policy "user_apns_devices_select_own"
  on public.user_apns_devices
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy "user_apns_devices_insert_own"
  on public.user_apns_devices
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "user_apns_devices_update_own"
  on public.user_apns_devices
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "user_apns_devices_delete_own"
  on public.user_apns_devices
  for delete
  to authenticated
  using (auth.uid() = user_id);
