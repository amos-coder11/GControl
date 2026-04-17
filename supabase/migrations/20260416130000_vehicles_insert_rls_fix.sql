-- =============================================================================
-- Simplifica la política INSERT de vehicles.
--
-- La política anterior exigía que organization_id o company_id del vehículo
-- coincidieran con funciones RLS que consultan tablas distintas a las que usa
-- la app (user_profiles vs profiles), provocando "new row violates row-level
-- security policy" al insertar desde iOS.
--
-- Nueva política: el usuario autenticado puede insertar filas cuyo user_id
-- sea el suyo. La app ya valida organización/empresa antes de enviar el INSERT.
-- =============================================================================

drop policy if exists vehicles_insert_own_tenant_authenticated on public.vehicles;

create policy vehicles_insert_own_authenticated
  on public.vehicles
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
  );
