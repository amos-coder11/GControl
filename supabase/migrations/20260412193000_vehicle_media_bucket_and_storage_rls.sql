-- RLS vehicles INSERT + bucket vehicle-media público + políticas Storage

drop policy if exists vehicles_insert_own_tenant_authenticated on public.vehicles;
drop policy if exists vehicles_insert_own_authenticated on public.vehicles;

create policy vehicles_insert_own_authenticated
  on public.vehicles
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
  );

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
