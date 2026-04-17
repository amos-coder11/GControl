-- Ficha extendida (app «Añadir vehículo»). Idempotente.
-- Útil si ya aplicaste una versión anterior de 20260415210000 sin estas columnas.

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
