-- Moderación de contenido generado por usuarios (App Store Guideline 1.2).

create table if not exists public.user_terms_acceptance (
  user_id uuid primary key references auth.users (id) on delete cascade,
  terms_version text not null,
  accepted_at timestamptz not null default now()
);

alter table public.user_terms_acceptance enable row level security;

create policy "user_terms_acceptance_select_own"
  on public.user_terms_acceptance
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy "user_terms_acceptance_insert_own"
  on public.user_terms_acceptance
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "user_terms_acceptance_update_own"
  on public.user_terms_acceptance
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

comment on table public.user_terms_acceptance is
  'Registro de aceptación del EULA / términos de tolerancia cero para UGC.';

-- Usuarios bloqueados por otro usuario (oculta contenido y notifica al desarrollador vía informe automático).
create table if not exists public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint blocked_users_distinct check (blocker_id <> blocked_id),
  constraint blocked_users_unique_pair unique (blocker_id, blocked_id)
);

create index if not exists blocked_users_blocker_idx
  on public.blocked_users (blocker_id);

alter table public.blocked_users enable row level security;

create policy "blocked_users_select_own"
  on public.blocked_users
  for select
  to authenticated
  using (auth.uid() = blocker_id);

create policy "blocked_users_insert_own"
  on public.blocked_users
  for insert
  to authenticated
  with check (auth.uid() = blocker_id and blocker_id <> blocked_id);

create policy "blocked_users_delete_own"
  on public.blocked_users
  for delete
  to authenticated
  using (auth.uid() = blocker_id);

comment on table public.blocked_users is
  'Pares bloqueador → bloqueado. El cliente oculta al instante el feed del bloqueador.';

-- Informes de contenido objetable (revisión del desarrollador en ≤24 h).
create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  reported_user_id uuid not null references auth.users (id) on delete cascade,
  content_type text not null,
  content_id uuid,
  content_preview text,
  reason text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint content_reports_status_check
    check (status in ('pending', 'reviewed', 'action_taken', 'dismissed'))
);

create index if not exists content_reports_status_created_idx
  on public.content_reports (status, created_at desc);

alter table public.content_reports enable row level security;

create policy "content_reports_insert_own"
  on public.content_reports
  for insert
  to authenticated
  with check (auth.uid() = reporter_id);

create policy "content_reports_select_own"
  on public.content_reports
  for select
  to authenticated
  using (auth.uid() = reporter_id);

comment on table public.content_reports is
  'Denuncias de UGC. El equipo de CarHub revisa y actúa en un plazo máximo de 24 horas.';
