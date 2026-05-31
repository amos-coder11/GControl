-- Crea filas de perfil al registrar un usuario en Supabase Auth.
-- Evita cuentas huérfanas sin fila en `profiles` / `user_profiles`.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_display_name text;
begin
  v_display_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(split_part(coalesce(new.email, ''), '@', 1)), ''),
    'Usuario'
  );

  if not exists (select 1 from public.profiles p where p.id = new.id) then
    insert into public.profiles (id, full_name)
    values (new.id, v_display_name);
  end if;

  if not exists (select 1 from public.user_profiles up where up.user_id = new.id) then
    insert into public.user_profiles (user_id, full_name)
    values (new.id, v_display_name);
  end if;

  return new;
exception
  when others then
    -- No bloquear el alta en Auth si el esquema local difiere.
    raise warning 'handle_new_auth_user failed for %: %', new.id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_auth_user();

comment on function public.handle_new_auth_user()
  is 'Bootstrap de profiles y user_profiles tras signUp en Supabase Auth.';
