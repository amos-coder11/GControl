-- =============================================================================
-- Esquema `public.vehicles` alineado con la app iOS (alta + lectura).
--
-- 1) Si la tabla no existe, se crea con columnas mínimas y tipos correctos.
-- 2) Si ya existe, se añaden solo las columnas que falten (idempotente).
--
-- Incluye: datos del coche, usuario, empresa/organización (RLS ya en otras
-- migraciones), Storage de fotos y marcas de tiempo.
--
-- Tras aplicar: Supabase suele refrescar la caché de PostgREST sola; si no,
-- Settings → API → reiniciar proyecto o esperar unos minutos.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Tabla nueva (proyectos sin `vehicles` todavía)
-- ---------------------------------------------------------------------------
create table if not exists public.vehicles (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    organization_id uuid,
    company_id uuid,
    marca text not null,
    modelo text not null,
    year integer not null,
    name text,
    license_plate text,
    price double precision,
    mileage integer,
    fuel_type text,
    transmission text,
    storage_path text,
    storage_bucket text,
    color text,
    vin text,
    trim text,
    power_cv integer,
    doors integer,
    seats integer,
    body_type text,
    drivetrain text,
    vehicle_condition text,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.vehicles is 'Inventario de vehículos. La app inserta marca/modelo + columnas en inglés (year, fuel_type, mileage…).';

-- ---------------------------------------------------------------------------
-- Columnas sueltas (tablas antiguas o creadas fuera de este repo)
-- ---------------------------------------------------------------------------
alter table if exists public.vehicles add column if not exists id uuid;
alter table if exists public.vehicles add column if not exists user_id uuid;
alter table if exists public.vehicles add column if not exists organization_id uuid;
alter table if exists public.vehicles add column if not exists company_id uuid;
alter table if exists public.vehicles add column if not exists marca text;
alter table if exists public.vehicles add column if not exists modelo text;
alter table if exists public.vehicles add column if not exists year integer;
alter table if exists public.vehicles add column if not exists name text;
alter table if exists public.vehicles add column if not exists license_plate text;
alter table if exists public.vehicles add column if not exists price double precision;
alter table if exists public.vehicles add column if not exists mileage integer;
alter table if exists public.vehicles add column if not exists fuel_type text;
alter table if exists public.vehicles add column if not exists transmission text;
alter table if exists public.vehicles add column if not exists storage_path text;
alter table if exists public.vehicles add column if not exists storage_bucket text;
alter table if exists public.vehicles add column if not exists color text;
alter table if exists public.vehicles add column if not exists vin text;
alter table if exists public.vehicles add column if not exists trim text;
alter table if exists public.vehicles add column if not exists power_cv integer;
alter table if exists public.vehicles add column if not exists doors integer;
alter table if exists public.vehicles add column if not exists seats integer;
alter table if exists public.vehicles add column if not exists body_type text;
alter table if exists public.vehicles add column if not exists drivetrain text;
alter table if exists public.vehicles add column if not exists vehicle_condition text;
alter table if exists public.vehicles add column if not exists notes text;
alter table if exists public.vehicles add column if not exists created_at timestamptz;
alter table if exists public.vehicles add column if not exists updated_at timestamptz;

-- Valores por defecto en columnas de tiempo (si la columna existe)
alter table if exists public.vehicles
    alter column created_at set default now();
alter table if exists public.vehicles
    alter column updated_at set default now();

-- Nota: si tu `vehicles` ya tenía `id` entero u otra PK, revisa a mano que
-- coincida con la app (la app inserta `id` uuid). No forzamos PK/FK aquí.

-- ---------------------------------------------------------------------------
-- Comentarios (documentación en Supabase)
-- ---------------------------------------------------------------------------
comment on column public.vehicles.user_id is 'Usuario que da de alta el vehículo (auth.uid() en INSERT).';
comment on column public.vehicles.organization_id is 'Tenant por organización (user_profiles.organization_id).';
comment on column public.vehicles.company_id is 'Tenant por empresa (profiles.company_id).';
comment on column public.vehicles.marca is 'Marca (equivalente a brand en la app).';
comment on column public.vehicles.modelo is 'Modelo (equivalente a model en la app).';
comment on column public.vehicles.year is 'Año del modelo.';
comment on column public.vehicles.name is 'Nombre mostrado; la app envía "Marca Modelo".';
comment on column public.vehicles.license_plate is 'Matrícula.';
comment on column public.vehicles.price is 'Precio (EUR, número).';
comment on column public.vehicles.mileage is 'Kilometraje.';
comment on column public.vehicles.fuel_type is 'Combustible / motor (texto libre).';
comment on column public.vehicles.transmission is 'Transmisión (texto libre).';
comment on column public.vehicles.storage_path is 'Ruta en Storage (p. ej. user_id/vehicle_id/001.jpg).';
comment on column public.vehicles.storage_bucket is 'Nombre del bucket (p. ej. vehicle-media).';
comment on column public.vehicles.color is 'Color exterior.';
comment on column public.vehicles.vin is 'Bastidor / VIN.';
comment on column public.vehicles.trim is 'Versión o acabado.';
comment on column public.vehicles.power_cv is 'Potencia en CV.';
comment on column public.vehicles.doors is 'Número de puertas.';
comment on column public.vehicles.seats is 'Plazas.';
comment on column public.vehicles.body_type is 'Carrocería (SUV, berlina…).';
comment on column public.vehicles.drivetrain is 'Tracción.';
comment on column public.vehicles.vehicle_condition is 'Estado: nuevo, ocasión, km0…';
comment on column public.vehicles.notes is 'Observaciones internas.';

-- ---------------------------------------------------------------------------
-- Índices útiles para listados por usuario / tenant
-- ---------------------------------------------------------------------------
create index if not exists idx_vehicles_user_id on public.vehicles (user_id);
create index if not exists idx_vehicles_year on public.vehicles (year desc);

-- ---------------------------------------------------------------------------
-- updated_at automático al hacer UPDATE
-- ---------------------------------------------------------------------------
create or replace function public.vehicles_set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists trg_vehicles_set_updated_at on public.vehicles;
create trigger trg_vehicles_set_updated_at
    before update on public.vehicles
    for each row
    execute function public.vehicles_set_updated_at();
