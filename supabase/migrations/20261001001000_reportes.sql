-- =====================================================================
-- Fase 2: reportes por día y por conductor
--
-- · Los días se cuentan en hora local de Oaxaca (America/Mexico_City), no
--   en UTC: un viaje de las 11:30 p. m. cuenta para ese día.
-- · SECURITY INVOKER: corren con los permisos de quien consulta, así que
--   RLS limita los datos (un despachador de sitio ve solo su sitio).
-- · "Ingresos" es una estimación: suma de tarifas de viajes completados.
--   Los viajes "a convenir" se cuentan aparte porque no tienen monto.
-- =====================================================================

create function public.reporte_por_dia(p_desde date, p_hasta date)
returns table (
  fecha                date,
  solicitados          bigint,
  completados          bigint,
  cancelados           bigint,
  cancelados_pasajero  bigint,
  sin_conductor        bigint,
  por_telefono         bigint,
  ingresos             numeric,
  a_convenir           bigint,
  minutos_asignacion   numeric
)
language plpgsql stable set search_path = '' as $$
declare
  v_tz text := 'America/Mexico_City';
begin
  if not public.es_staff() then
    raise exception 'No tienes permiso para esta acción' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 366 then
    raise exception 'Elige un rango de fechas válido (máximo un año)'
      using errcode = 'P0001', hint = 'rango_invalido';
  end if;

  return query
  with v as (
    select vi.id, vi.estado, vi.canal, vi.tarifa_monto, vi.solicitado_en, vi.asignado_en,
           (vi.solicitado_en at time zone v_tz)::date as dia,
           p.rol as rol_cancelo
    from public.viajes vi
    left join public.perfiles p on p.id = vi.cancelado_por
    where vi.solicitado_en >= (p_desde::timestamp at time zone v_tz)
      and vi.solicitado_en < ((p_hasta + 1)::timestamp at time zone v_tz)
  )
  select d.dia,
         count(v.id),
         count(v.id) filter (where v.estado = 'completado'),
         count(v.id) filter (where v.estado = 'cancelado'),
         count(v.id) filter (where v.estado = 'cancelado' and v.rol_cancelo = 'pasajero'),
         count(v.id) filter (where v.estado = 'sin_conductor'),
         count(v.id) filter (where v.canal = 'telefono'),
         coalesce(sum(v.tarifa_monto) filter (where v.estado = 'completado'), 0),
         count(v.id) filter (where v.estado = 'completado' and v.tarifa_monto is null),
         round(avg(extract(epoch from v.asignado_en - v.solicitado_en) / 60)
               filter (where v.asignado_en is not null), 1)
  from generate_series(p_desde, p_hasta, interval '1 day') as g (d)
  cross join lateral (select g.d::date as dia) as d
  left join v on v.dia = d.dia
  group by d.dia
  order by d.dia;
end;
$$;

-- Ofertas: "vencidas" son las que el conductor dejó pasar el tiempo;
-- las retiradas antes de vencer (el pasajero canceló, el despacho asignó
-- a otro) no cuentan en su contra. Las filas 'soltada' no son ofertas.
create function public.reporte_por_conductor(p_desde date, p_hasta date)
returns table (
  conductor_id  uuid,
  nombre        text,
  sitio         text,
  activo        boolean,
  completados   bigint,
  ingresos      numeric,
  a_convenir    bigint,
  ofertas       bigint,
  aceptadas     bigint,
  rechazadas    bigint,
  vencidas      bigint,
  soltados      bigint
)
language plpgsql stable set search_path = '' as $$
declare
  v_tz     text := 'America/Mexico_City';
  v_desde  timestamptz;
  v_hasta  timestamptz;
begin
  if not public.es_staff() then
    raise exception 'No tienes permiso para esta acción' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 366 then
    raise exception 'Elige un rango de fechas válido (máximo un año)'
      using errcode = 'P0001', hint = 'rango_invalido';
  end if;

  v_desde := p_desde::timestamp at time zone v_tz;
  v_hasta := (p_hasta + 1)::timestamp at time zone v_tz;

  return query
  with viajes as (
    select vi.conductor_id,
           count(*) filter (where vi.estado = 'completado') as completados,
           coalesce(sum(vi.tarifa_monto) filter (where vi.estado = 'completado'), 0) as ingresos,
           count(*) filter (where vi.estado = 'completado' and vi.tarifa_monto is null) as a_convenir
    from public.viajes vi
    where vi.conductor_id is not null
      and vi.solicitado_en >= v_desde and vi.solicitado_en < v_hasta
    group by vi.conductor_id
  ),
  ofertas as (
    select o.conductor_id,
           count(*) as ofertas,
           count(*) filter (where o.respuesta = 'aceptada') as aceptadas,
           count(*) filter (where o.respuesta = 'rechazada') as rechazadas,
           count(*) filter (where o.respuesta = 'expirada' and o.respondido_en >= o.expira_en) as vencidas
    from public.ofertas_viaje o
    where o.respuesta <> 'soltada'
      and o.ofrecido_en >= v_desde and o.ofrecido_en < v_hasta
    group by o.conductor_id
  ),
  soltados as (
    select e.actor_id as conductor_id, count(*) as soltados
    from public.viaje_eventos e
    where e.estado_nuevo = 'buscando'
      and e.estado_anterior in ('asignado', 'conductor_llego')
      and e.ocurrido_en >= v_desde and e.ocurrido_en < v_hasta
    group by e.actor_id
  )
  select c.perfil_id, p.nombre, s.nombre, c.activo,
         coalesce(vj.completados, 0), coalesce(vj.ingresos, 0), coalesce(vj.a_convenir, 0),
         coalesce(o.ofertas, 0), coalesce(o.aceptadas, 0), coalesce(o.rechazadas, 0),
         coalesce(o.vencidas, 0), coalesce(so.soltados, 0)
  from public.conductores c
  join public.perfiles p on p.id = c.perfil_id
  join public.sitios s on s.id = c.sitio_id
  left join viajes vj on vj.conductor_id = c.perfil_id
  left join ofertas o on o.conductor_id = c.perfil_id
  left join soltados so on so.conductor_id = c.perfil_id
  -- Inactivos solo si tuvieron actividad en el periodo.
  where c.activo or vj.conductor_id is not null or o.conductor_id is not null or so.conductor_id is not null
  order by coalesce(vj.completados, 0) desc, p.nombre;
end;
$$;

revoke execute on function public.reporte_por_dia(date, date), public.reporte_por_conductor(date, date)
  from public, anon;
grant execute on function public.reporte_por_dia(date, date), public.reporte_por_conductor(date, date)
  to authenticated;
