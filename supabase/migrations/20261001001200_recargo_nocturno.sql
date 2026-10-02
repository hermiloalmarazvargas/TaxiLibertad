-- =====================================================================
-- Recargo nocturno
-- · Porcentaje sobre la tarifa entre zonas, en un horario (hora de Oaxaca)
--   que puede cruzar la medianoche (p. ej. 22:00 a 06:00).
-- · Se aplica según la hora en que se PIDE el viaje y se redondea al peso.
-- · Los viajes "a convenir" siguen a convenir (solo se indica que es de noche).
-- · El admin cambia porcentaje y horario desde el panel (tabla configuracion).
-- =====================================================================

-- Configuración general: una sola fila.
create table public.configuracion (
  id                    boolean primary key default true check (id),
  recargo_nocturno_pct  numeric(5, 2) not null default 10
                        check (recargo_nocturno_pct between 0 and 100),
  recargo_desde         time not null default '22:00',
  recargo_hasta         time not null default '06:00',
  actualizado_por       uuid references public.perfiles (id) on delete set null,
  actualizado_en        timestamptz not null default now()
);

insert into public.configuracion default values;

alter table public.configuracion enable row level security;

grant select on public.configuracion to authenticated;
grant update (recargo_nocturno_pct, recargo_desde, recargo_hasta) on public.configuracion to authenticated;

create policy "usuarios con rol leen la configuracion"
  on public.configuracion for select to authenticated
  using ((select public.rol_actual()) is not null);

create policy "admin cambia la configuracion"
  on public.configuracion for update to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- Mismo registro de quién/cuándo que en tarifas.
create trigger configuracion_marcar_cambio
  before update on public.configuracion
  for each row execute function privado.tarifa_marcar_cambio();

-- El recargo cobrado queda guardado aparte (ya está incluido en tarifa_monto).
alter table public.viajes
  add column tarifa_recargo numeric(8, 2) check (tarifa_recargo >= 0);

-- ---------------------------------------------------------------------
-- tarifa_estimada: ahora con recargo nocturno
-- (cambia lo que devuelve, por eso se borra y se vuelve a crear)
-- ---------------------------------------------------------------------
drop function public.tarifa_estimada(double precision, double precision, double precision, double precision);

-- monto       = lo que se cobra (null = a convenir)
-- monto_base  = tarifa entre zonas sin recargo
-- recargo     = pesos de recargo nocturno (0 de día; null si es a convenir)
-- nocturno    = si en ese momento aplica el horario nocturno
create function public.tarifa_estimada(
  origen_lat   double precision,
  origen_lng   double precision,
  destino_lat  double precision default null,
  destino_lng  double precision default null,
  momento      timestamptz default now()
)
returns table (
  zona_origen_id   bigint,
  zona_origen      text,
  zona_destino_id  bigint,
  zona_destino     text,
  monto            numeric,
  monto_base       numeric,
  recargo          numeric,
  nocturno         boolean
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
  ),
  base as (
    select o.id as origen_id, d.id as destino_id, t.monto
    from o
    cross join d
    left join public.tarifas t on t.zona_origen_id = o.id and t.zona_destino_id = d.id
  ),
  noche as (
    select c.recargo_nocturno_pct as pct,
           c.recargo_nocturno_pct > 0 and case
             when c.recargo_desde = c.recargo_hasta then false
             when c.recargo_desde < c.recargo_hasta then h.hora >= c.recargo_desde and h.hora < c.recargo_hasta
             else h.hora >= c.recargo_desde or h.hora < c.recargo_hasta  -- cruza la medianoche
           end as aplica
    from public.configuracion c
    cross join (select (momento at time zone 'America/Mexico_City')::time as hora) as h
  ),
  calculo as (
    select b.*,
           case
             when b.monto is null then null
             when coalesce(n.aplica, false) then round(b.monto * n.pct / 100)
             else 0
           end as recargo,
           coalesce(n.aplica, false) as nocturno
    from base b
    left join noche n on true
  )
  select k.origen_id, zo.nombre, k.destino_id, zd.nombre,
         k.monto + k.recargo, k.monto, k.recargo, k.nocturno
  from calculo k
  left join public.zonas zo on zo.id = k.origen_id
  left join public.zonas zd on zd.id = k.destino_id;
$$;

revoke execute on function public.tarifa_estimada(double precision, double precision, double precision, double precision, timestamptz)
  from public, anon;
grant execute on function public.tarifa_estimada(double precision, double precision, double precision, double precision, timestamptz)
  to authenticated;

-- ---------------------------------------------------------------------
-- insertar_viaje: guarda también el recargo cobrado
-- ---------------------------------------------------------------------
create or replace function privado.insertar_viaje(
  p_canal              public.canal_viaje,
  p_client_request_id  uuid,
  p_pasajero_id        uuid,
  p_contacto_nombre    text,
  p_contacto_telefono  text,
  p_origen_lat         double precision,
  p_origen_lng         double precision,
  p_origen_referencia  text,
  p_destino_lat        double precision,
  p_destino_lng        double precision,
  p_destino_referencia text
) returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_tarifa  record;
  v_viaje   public.viajes;
begin
  perform privado.validar_coordenadas(p_origen_lat, p_origen_lng);
  if (p_destino_lat is null) <> (p_destino_lng is null) then
    perform privado.error('coordenadas_invalidas', 'El destino no es válido');
  end if;
  if p_destino_lat is not null then
    perform privado.validar_coordenadas(p_destino_lat, p_destino_lng);
  end if;

  select * into v_tarifa
  from public.tarifa_estimada(p_origen_lat, p_origen_lng, p_destino_lat, p_destino_lng);

  insert into public.viajes (
    client_request_id, canal, pasajero_id, creado_por, contacto_nombre, contacto_telefono,
    origen, origen_referencia, destino, destino_referencia,
    zona_origen_id, zona_destino_id, tarifa_monto, tarifa_recargo
  ) values (
    p_client_request_id, p_canal, p_pasajero_id, auth.uid(),
    nullif(trim(p_contacto_nombre), ''), p_contacto_telefono,
    public.punto(p_origen_lat, p_origen_lng), nullif(trim(p_origen_referencia), ''),
    case when p_destino_lat is not null then public.punto(p_destino_lat, p_destino_lng) end,
    nullif(trim(p_destino_referencia), ''),
    v_tarifa.zona_origen_id, v_tarifa.zona_destino_id, v_tarifa.monto, v_tarifa.recargo
  )
  returning * into v_viaje;

  return v_viaje;
end;
$$;

revoke all on all functions in schema privado from public, anon, authenticated;
