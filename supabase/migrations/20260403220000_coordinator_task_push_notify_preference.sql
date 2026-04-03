-- Push al crear tarea Viera (`team_coordinator_tasks`) vía `notify_send_message_push`.
-- Preferencia `notify_team_push` en `user_profiles`: por defecto true; si false, la Edge Function no envía APNs al destinatario.

alter table public.user_profiles
  add column if not exists notify_team_push boolean not null default true;

comment on column public.user_profiles.notify_team_push is
  'Si es false, no se envían notificaciones push de equipo (mensajes/tareas) a este usuario.';

-- Actualización de la fila propia (ubicación, este flag, etc.).
drop policy if exists "user_profiles_update_own_row" on public.user_profiles;

create policy "user_profiles_update_own_row"
  on public.user_profiles
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists trg_team_coordinator_tasks_send_push on public.team_coordinator_tasks;

create trigger trg_team_coordinator_tasks_send_push
  after insert on public.team_coordinator_tasks
  for each row
  execute function public.notify_send_message_push();
