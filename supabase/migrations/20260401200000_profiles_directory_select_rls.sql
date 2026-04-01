-- Mapa de equipo: los usuarios autenticados deben poder LEER todas las filas de `profiles`
-- (lat/lon, avatar, nombre) para ver a todos los que usan la app con ubicación compartida.
-- La app solo actualiza la fila propia (CommunityProfilesService.pushMyLocation).

alter table if exists public.profiles enable row level security;

drop policy if exists "profiles_read_all_authenticated" on public.profiles;

create policy "profiles_read_all_authenticated"
  on public.profiles
  for select
  to authenticated
  using (true);

-- Actualización: cada usuario solo su fila (por si no existía aún).
drop policy if exists "profiles_update_own_row" on public.profiles;

create policy "profiles_update_own_row"
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Realtime (opcional): en Supabase → Database → Publications → supabase_realtime,
-- incluye la tabla `profiles` para recibir cambios en vivo sin depender solo del polling de la app.
