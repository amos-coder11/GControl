-- Cabecera opcional x-push-secret para coincidir con Edge secret PUSH_WEBHOOK_SECRET.
-- 1) En Supabase → Edge Functions → Secrets: si tienes PUSH_WEBHOOK_SECRET, copia el mismo valor aquí:
--    update private.push_delivery_config set webhook_secret = 'TU_MISMO_VALOR' where id = 1;
-- 2) Si webhook_secret es null, el trigger no envía la cabecera (la función solo exige secret si está definido en Edge).

create schema if not exists private;

create table if not exists private.push_delivery_config (
  id int primary key default 1 check (id = 1),
  webhook_secret text
);

insert into private.push_delivery_config (id, webhook_secret)
values (1, null)
on conflict (id) do nothing;

revoke all on private.push_delivery_config from public;
grant all on private.push_delivery_config to postgres;
grant all on private.push_delivery_config to service_role;

create or replace function public.notify_send_message_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  sec text;
  hdr jsonb;
begin
  select c.webhook_secret into sec
  from private.push_delivery_config c
  where c.id = 1;

  payload := jsonb_build_object(
    'type', 'INSERT',
    'table', tg_table_name,
    'record', to_jsonb(new)
  );

  hdr := jsonb_build_object('Content-Type', 'application/json');
  if sec is not null and length(trim(sec)) > 0 then
    hdr := hdr || jsonb_build_object('x-push-secret', sec);
  end if;

  perform net.http_post(
    url := 'https://fwdfhbgcurimqufbwkux.supabase.co/functions/v1/send-message-push',
    headers := hdr,
    body := payload
  );
  return new;
end;
$$;
