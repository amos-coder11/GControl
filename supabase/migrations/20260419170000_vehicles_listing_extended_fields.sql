-- Campos ampliados de ficha / anuncio (alta desde app). Idempotente.

alter table if exists public.vehicles add column if not exists purchase_price double precision;
alter table if exists public.vehicles add column if not exists market_price double precision;
alter table if exists public.vehicles add column if not exists financed_price double precision;
alter table if exists public.vehicles add column if not exists listing_description text;
alter table if exists public.vehicles add column if not exists listing_extra jsonb;
alter table if exists public.vehicles add column if not exists dgt_label text;

comment on column public.vehicles.purchase_price is 'Precio de compra (€).';
comment on column public.vehicles.market_price is 'Precio de mercado estimado (€).';
comment on column public.vehicles.financed_price is 'Precio financiado orientativo (€).';
comment on column public.vehicles.listing_description is 'Descripción del anuncio (texto largo).';
comment on column public.vehicles.listing_extra is 'JSON: categoría, IVA, equipamiento, dueño, publicación en portales, etc.';
