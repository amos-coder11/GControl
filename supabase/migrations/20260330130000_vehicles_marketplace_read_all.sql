-- Catálogo compartido: que TODAS las cuentas (authenticated) y la app con clave anon
-- vean los mismos vehículos en marketplace (misma idea que un escaparate único).
--
-- Síntoma en la app: un usuario (p. ej. Jesús Castillo) ve filas y otros no → suele haber
-- políticas del tipo (user_id = auth.uid()) sin otra política que abra el listado público.
--
-- Ejecuta en Supabase → SQL Editor. Revisa nombres de tabla/columnas; si tu inventario no
-- es "public.vehicles", sustituye o duplica este archivo.

alter table if exists public.vehicles enable row level security;

-- Evita duplicar el mismo nombre si reaplicas la migración
drop policy if exists vehicles_marketplace_select_authenticated on public.vehicles;
drop policy if exists vehicles_marketplace_select_anon on public.vehicles;

-- Cualquier usuario con sesión Supabase Auth puede LEER todas las filas del inventario.
-- Producción: sustituye USING (true) por tu regla (p. ej. solo publicados):
--   using (coalesce(online_listing, false) = true)
-- o por no borrados:
--   using (deleted_at is null)
create policy vehicles_marketplace_select_authenticated
  on public.vehicles
  for select
  to authenticated
  using (true);

-- Listado sin login (clave anon en la app): necesario para el cliente "catalogAnon" y
-- para que el escaparate sea coherente entre sesiones. Ajusta USING en producción igual que arriba.
create policy vehicles_marketplace_select_anon
  on public.vehicles
  for select
  to anon
  using (true);

-- Notas:
-- 1) Si ya tienes otras políticas SELECT restrictivas, Postgres las combina en modo PERMISSIVE
--    con OR: basta que una permita la fila. Si usas políticas RESTRICTIVE, revisa la doc.
-- 2) INSERT/UPDATE/DELETE deben seguir con políticas separadas (solo el propietario, etc.).
-- 3) Tras aplicar, prueba con otra cuenta en Table Editor → "View as user" o desde la app.
