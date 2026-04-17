-- =============================================================================
-- Filtrado por empresa: cada integrante solo ve los vehículos de su empresa.
-- =============================================================================
--
-- 1) Añade `company_id` a `profiles` y a `vehicles`.
-- 2) Actualiza las políticas RLS de `vehicles` para que el SELECT filtre
--    por la empresa del usuario autenticado (`profiles.company_id`).
-- 3) Reemplaza la RPC `marketplace_vehicles_page` para aceptar `p_company_id`
--    y filtrar por empresa.
-- 4) Mantiene acceso anon (escaparate público) solo para filas cuyo
--    `company_id IS NULL` (coches sin empresa asignada, catálogo demo).
--    Si prefieres que anon no vea nada, cambia la política anon a `using (false)`.
--
-- Ejecutar en: Supabase → SQL Editor.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Columnas company_id
-- ---------------------------------------------------------------------------

-- En profiles: cada usuario pertenece a una empresa.
alter table if exists public.profiles
    add column if not exists company_id uuid;

comment on column public.profiles.company_id
    is 'Empresa a la que pertenece el usuario. NULL = sin empresa asignada.';

-- Índice para búsquedas rápidas por empresa en profiles.
create index if not exists idx_profiles_company_id on public.profiles (company_id);

-- En vehicles: cada vehículo pertenece a una empresa.
alter table if exists public.vehicles
    add column if not exists company_id uuid;

comment on column public.vehicles.company_id
    is 'Empresa propietaria del vehículo. NULL = catálogo público / demo.';

-- Índice para filtrar vehículos por empresa rápidamente.
create index if not exists idx_vehicles_company_id on public.vehicles (company_id);

-- ---------------------------------------------------------------------------
-- 2. Función auxiliar: obtener company_id del usuario autenticado
-- ---------------------------------------------------------------------------

create or replace function public.auth_user_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select company_id
  from public.profiles
  where id = auth.uid()
  limit 1;
$$;

comment on function public.auth_user_company_id()
    is 'Devuelve el company_id del usuario con sesión activa (desde profiles).';

-- ---------------------------------------------------------------------------
-- 3. Políticas RLS actualizadas en vehicles
-- ---------------------------------------------------------------------------

-- Eliminar las políticas anteriores (escaparate único).
drop policy if exists vehicles_marketplace_select_authenticated on public.vehicles;
drop policy if exists vehicles_marketplace_select_anon on public.vehicles;

-- Authenticated: solo ve vehículos de su misma empresa,
-- O vehículos sin empresa (catálogo público/demo).
-- Si el usuario no tiene company_id asignado, solo ve los de company_id IS NULL.
create policy vehicles_company_select_authenticated
  on public.vehicles
  for select
  to authenticated
  using (
    company_id is null
    or company_id = public.auth_user_company_id()
  );

-- Anon: solo catálogo público (sin empresa), si quieres deshabilitar cambia a using(false).
create policy vehicles_company_select_anon
  on public.vehicles
  for select
  to anon
  using (company_id is null);

-- ---------------------------------------------------------------------------
-- 4. RPC marketplace_vehicles_page con filtro por empresa
-- ---------------------------------------------------------------------------

-- Reemplazar la RPC existente para que acepte un filtro opcional de empresa.
drop function if exists public.marketplace_vehicles_page(integer, integer);

create or replace function public.marketplace_vehicles_page(
    p_limit integer,
    p_offset integer,
    p_company_id uuid default null
)
returns setof public.vehicles
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.vehicles
  where
    case
      when p_company_id is not null then
        company_id = p_company_id or company_id is null
      else
        true
    end
  order by id
  limit greatest(1, least(p_limit, 200))
  offset greatest(0, p_offset);
$$;

revoke all on function public.marketplace_vehicles_page(integer, integer, uuid) from public;
grant execute on function public.marketplace_vehicles_page(integer, integer, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. RPC auxiliar: obtener company_id del usuario actual (para el cliente iOS)
-- ---------------------------------------------------------------------------

create or replace function public.get_my_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select company_id
  from public.profiles
  where id = auth.uid()
  limit 1;
$$;

revoke all on function public.get_my_company_id() from public;
grant execute on function public.get_my_company_id() to authenticated;

comment on function public.get_my_company_id()
    is 'Devuelve el company_id del usuario autenticado para uso desde el cliente iOS.';
