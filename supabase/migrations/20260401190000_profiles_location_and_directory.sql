-- Columnas para mapa en vivo y nombre en el carrusel de Inicio.
-- Ajusta las políticas RLS en el panel de Supabase: los usuarios autenticados
-- deben poder leer filas de `profiles` (directorio) y actualizar solo la propia (ubicación).

alter table if exists public.profiles
    add column if not exists full_name text;

alter table if exists public.profiles
    add column if not exists latitude double precision;

alter table if exists public.profiles
    add column if not exists longitude double precision;

alter table if exists public.profiles
    add column if not exists location_updated_at timestamptz;

comment on column public.profiles.latitude is 'Última latitud compartida (mapa Inicio).';
comment on column public.profiles.longitude is 'Última longitud compartida.';
