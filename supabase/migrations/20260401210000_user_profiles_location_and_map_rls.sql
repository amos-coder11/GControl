-- Tabla real del proyecto: `user_profiles` (auth.uid() = user_id).
-- Mapa de equipo: lectura del directorio + columnas de ubicación.

alter table public.user_profiles
    add column if not exists latitude double precision;

alter table public.user_profiles
    add column if not exists longitude double precision;

alter table public.user_profiles
    add column if not exists location_updated_at timestamptz;

comment on column public.user_profiles.latitude is 'Última latitud compartida (mapa Inicio).';
comment on column public.user_profiles.longitude is 'Última longitud compartida.';

alter table public.user_profiles enable row level security;

-- Cualquier usuario autenticado puede ver todos los perfiles (mapa / carrusel).
drop policy if exists "user_profiles_select_directory" on public.user_profiles;

create policy "user_profiles_select_directory"
  on public.user_profiles
  for select
  to authenticated
  using (true);
