-- Audio de notas de voz en DMs de equipo (ruta en `team_direct_messages.body` con prefijo CARHUB_VOICE_V1:).

insert into storage.buckets (id, name, public)
values ('team_direct_voice', 'team_direct_voice', false)
on conflict (id) do nothing;

-- Ruta: {sender_id}/{recipient_id}/{uuid}.m4a (UUID en minúsculas, coincide con auth.uid()::text).
drop policy if exists "team_direct_voice_insert_sender" on storage.objects;
create policy "team_direct_voice_insert_sender"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'team_direct_voice'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "team_direct_voice_select_participants" on storage.objects;
create policy "team_direct_voice_select_participants"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'team_direct_voice'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or (storage.foldername(name))[2] = auth.uid()::text
    )
  );
