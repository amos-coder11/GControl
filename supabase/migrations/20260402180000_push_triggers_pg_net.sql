-- Dispara la Edge Function `send-message-push` en cada INSERT de mensaje (evita depender del panel Webhooks).
-- Requiere extensión pg_net (habitual en Supabase).
-- Si en Edge Functions → Secrets tienes PUSH_WEBHOOK_SECRET, quítalo o la función responderá 401
-- (este trigger no envía x-push-secret).

create or replace function public.notify_send_message_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
begin
  payload := jsonb_build_object(
    'type', 'INSERT',
    'table', tg_table_name,
    'record', to_jsonb(new)
  );
  perform net.http_post(
    url := 'https://fwdfhbgcurimqufbwkux.supabase.co/functions/v1/send-message-push',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := payload
  );
  return new;
end;
$$;

drop trigger if exists trg_team_direct_messages_send_push on public.team_direct_messages;
create trigger trg_team_direct_messages_send_push
  after insert on public.team_direct_messages
  for each row
  execute function public.notify_send_message_push();

drop trigger if exists trg_team_group_messages_send_push on public.team_group_messages;
create trigger trg_team_group_messages_send_push
  after insert on public.team_group_messages
  for each row
  execute function public.notify_send_message_push();
