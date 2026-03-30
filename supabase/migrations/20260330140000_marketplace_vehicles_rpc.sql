-- RPC de catálogo compartido: lectura paginada de public.vehicles con el mismo resultado para
-- anon y authenticated (SECURITY DEFINER evita que RLS por fila bloquee el marketplace).
--
-- Ejecutar en Supabase → SQL Editor. Luego comprueba en API que el esquema public expone la función.

create or replace function public.marketplace_vehicles_page(p_limit integer, p_offset integer)
returns setof public.vehicles
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.vehicles
  order by id
  limit greatest(1, least(p_limit, 200))
  offset greatest(0, p_offset);
$$;

revoke all on function public.marketplace_vehicles_page(integer, integer) from public;
grant execute on function public.marketplace_vehicles_page(integer, integer) to anon, authenticated;
