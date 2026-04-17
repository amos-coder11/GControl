-- Storage vehicle-media: RLS compatible con UUID en mayúsculas/minúsculas y upsert (UPDATE).

drop policy if exists storage_vehicle_media_insert on storage.objects;
create policy storage_vehicle_media_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'vehicle-media'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

drop policy if exists storage_vehicle_media_update on storage.objects;
create policy storage_vehicle_media_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'vehicle-media'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  )
  with check (
    bucket_id = 'vehicle-media'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

drop policy if exists storage_vehicle_media_select on storage.objects;
create policy storage_vehicle_media_select
  on storage.objects
  for select
  to public
  using (
    bucket_id = 'vehicle-media'
  );
