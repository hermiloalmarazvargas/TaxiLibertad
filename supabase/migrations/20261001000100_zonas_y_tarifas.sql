-- =====================================================================
-- Fase 1 · Paso 1: funciones de zonas y tarifa estimada
-- =====================================================================

-- Construye un punto geográfico a partir de latitud/longitud.
create or replace function public.punto(lat double precision, lng double precision)
returns extensions.geography
language sql
immutable
set search_path = ''
as $$
  select extensions.st_setsrid(extensions.st_makepoint(lng, lat), 4326)::extensions.geography;
$$;

-- Zona activa que contiene el punto; si hay traslape, la de menor área.
-- Devuelve null si el punto no está en ninguna zona.
create or replace function public.zona_de(p extensions.geography)
returns bigint
language sql
stable
set search_path = ''
as $$
  select z.id
  from public.zonas z
  where z.activa
    and extensions.st_contains(z.poligono, p::extensions.geometry)
  order by extensions.st_area(z.poligono)
  limit 1;
$$;

-- Tarifa estimada entre dos puntos. monto = null significa "a convenir"
-- (sin destino, fuera de zonas o sin tarifa capturada para ese par).
create or replace function public.tarifa_estimada(
  origen_lat   double precision,
  origen_lng   double precision,
  destino_lat  double precision default null,
  destino_lng  double precision default null
)
returns table (
  zona_origen_id   bigint,
  zona_origen      text,
  zona_destino_id  bigint,
  zona_destino     text,
  monto            numeric
)
language sql
stable
set search_path = ''
as $$
  with o as (
    select public.zona_de(public.punto(origen_lat, origen_lng)) as id
  ),
  d as (
    select case
             when destino_lat is null or destino_lng is null then null
             else public.zona_de(public.punto(destino_lat, destino_lng))
           end as id
  )
  select o.id, zo.nombre, d.id, zd.nombre, t.monto
  from o
  cross join d
  left join public.zonas zo on zo.id = o.id
  left join public.zonas zd on zd.id = d.id
  left join public.tarifas t
    on t.zona_origen_id = o.id and t.zona_destino_id = d.id;
$$;
