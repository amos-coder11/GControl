-- Reaplicar bucket vehicle-media y políticas Storage (idempotente)

insert into storage.buckets (id, name, public)
values ('vehicle-media', 'vehicle-media', true)
on conflict (id) do update set public = true;

drop policy if exists storage_vehicle_media_insert on storage.objects;
create policy storage_vehicle_media_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'vehicle-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists storage_vehicle_media_select on storage.objects;
create policy storage_vehicle_media_select
  on storage.objects
  for select
  to public
  using (
    bucket_id = 'vehicle-media'
  );
