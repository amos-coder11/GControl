-- =============================================================================
-- Alta de vehículos desde clientes autenticados, aislado por organización o empresa.
-- =============================================================================
-- - Añade `organization_id` en `vehicles` si falta (alineado con `user_profiles`).
-- - Función `auth_user_organization_id()` (SECURITY DEFINER).
-- - Política INSERT: `user_id = auth.uid()` y el vehículo pertenece al tenant del usuario.
-- Ejecutar en Supabase → SQL Editor si no aplicás migraciones por CLI.
-- =============================================================================

alter table if exists public.vehicles
    add column if not exists organization_id uuid;

comment on column public.vehicles.organization_id
    is 'Organización propietaria (multi‑cuenta). Debe coincidir con user_profiles.organization_id del vendedor.';

create index if not exists idx_vehicles_organization_id on public.vehicles (organization_id);

create or replace function public.auth_user_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id
  from public.user_profiles
  where user_id = auth.uid()
  limit 1;
$$;

comment on function public.auth_user_organization_id()
    is 'organization_id del usuario con sesión (tabla user_profiles).';

revoke all on function public.auth_user_organization_id() from public;
grant execute on function public.auth_user_organization_id() to authenticated;

-- Lectura: los usuarios autenticados también ven el inventario de su organización.
drop policy if exists vehicles_company_select_authenticated on public.vehicles;

create policy vehicles_company_select_authenticated
  on public.vehicles
  for select
  to authenticated
  using (
    company_id is null
    or company_id = public.auth_user_company_id()
    or (
      organization_id is not null
      and organization_id = public.auth_user_organization_id()
    )
  );

-- INSERT: solo en nombre del propio usuario y del tenant asignado.
drop policy if exists vehicles_insert_own_tenant_authenticated on public.vehicles;

create policy vehicles_insert_own_tenant_authenticated
  on public.vehicles
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and (
      (
        public.auth_user_organization_id() is not null
        and organization_id = public.auth_user_organization_id()
      )
      or
      (
        public.auth_user_organization_id() is null
        and public.auth_user_company_id() is not null
        and company_id = public.auth_user_company_id()
        and organization_id is null
      )
    )
  );
