-- Portada en tabla tras subir a Storage: `main_image_url` + RLS UPDATE para el propietario.

alter table if exists public.vehicles add column if not exists main_image_url text;

comment on column public.vehicles.main_image_url is 'URL https de la portada (p. ej. object/public/vehicle-media/.../001.jpg).';

drop policy if exists vehicles_update_own_authenticated on public.vehicles;

create policy vehicles_update_own_authenticated
  on public.vehicles
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
