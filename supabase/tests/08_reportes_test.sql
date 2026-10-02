-- Pruebas: reportes por día y por conductor, y ofertas "soltadas".
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000008' || s)::uuid, s || '@reportes.local'
from unnest(array['d0', 'd1', 'c1', 'c2', 'c3', 'e1', 'e2']) as s;

create function pg_temp.uid(p text) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-0000000008' || p)::uuid $$;

insert into public.sitios (nombre) values ('Rep Sitio A'), ('Rep Sitio B');

create function pg_temp.sitio(p text) returns bigint language sql stable
as $$ select id from public.sitios where nombre = 'Rep Sitio ' || p $$;

insert into public.unidades (sitio_id, numero_economico, placas) values
  (pg_temp.sitio('A'), 'RA-1', 'REP0001'),
  (pg_temp.sitio('B'), 'RB-1', 'REP0002'),
  (pg_temp.sitio('A'), 'RA-3', 'REP0003');

create function pg_temp.unidad(p text) returns bigint language sql security definer
as $$ select id from public.unidades where placas = p $$;

insert into public.perfiles (id, rol, nombre, usuario, telefono, sitio_id) values
  (pg_temp.uid('d0'), 'despachador', 'Central', 'rep.d0', null, null),
  (pg_temp.uid('d1'), 'despachador', 'Despacho A', 'rep.d1', null, pg_temp.sitio('A')),
  (pg_temp.uid('c1'), 'conductor', 'Chofer A', 'rep.c1', null, null),
  (pg_temp.uid('c2'), 'conductor', 'Chofer B', 'rep.c2', null, null),
  (pg_temp.uid('c3'), 'conductor', 'Chofer A3', 'rep.c3', null, null),
  (pg_temp.uid('e1'), 'pasajero', 'Pasajero', null, '+529512220001', null),
  (pg_temp.uid('e2'), 'pasajero', 'Pasajero 2', null, '+529512220002', null);

insert into public.conductores (perfil_id, sitio_id) values
  (pg_temp.uid('c1'), pg_temp.sitio('A')),
  (pg_temp.uid('c2'), pg_temp.sitio('B')),
  (pg_temp.uid('c3'), pg_temp.sitio('A'));

-- ── Viajes con horas a propósito cerca de la medianoche ──────────────
-- (las horas van con -06, la hora de Oaxaca)
insert into public.viajes
  (id, canal, pasajero_id, origen, estado, conductor_id, unidad_id, sitio_id, tarifa_monto,
   solicitado_en, asignado_en, cancelado_por)
values
  -- 10 de marzo, 6 p. m. local = 11 de marzo 00:00 UTC → cuenta el día 10
  ('00000000-0000-0000-0000-00000000bb01', 'app', pg_temp.uid('e1'), public.punto(16.33, -96.6),
   'completado', pg_temp.uid('c1'), pg_temp.unidad('REP0001'), pg_temp.sitio('A'), 45,
   '2026-03-10 18:00-06', '2026-03-10 18:03-06', null),
  ('00000000-0000-0000-0000-00000000bb02', 'app', pg_temp.uid('e1'), public.punto(16.33, -96.6),
   'completado', pg_temp.uid('c1'), pg_temp.unidad('REP0001'), pg_temp.sitio('A'), null,
   '2026-03-10 15:00-06', '2026-03-10 15:05-06', null),
  ('00000000-0000-0000-0000-00000000bb03', 'app', pg_temp.uid('e1'), public.punto(16.33, -96.6),
   'cancelado', null, null, null, null,
   '2026-03-10 10:00-06', null, pg_temp.uid('e1')),
  ('00000000-0000-0000-0000-00000000bb04', 'telefono', null, public.punto(16.33, -96.6),
   'sin_conductor', null, null, null, null,
   '2026-03-11 09:00-06', null, null),
  -- 11 de marzo, 11:30 p. m. local = 12 de marzo 05:30 UTC → cuenta el día 11
  ('00000000-0000-0000-0000-00000000bb05', 'app', pg_temp.uid('e1'), public.punto(16.33, -96.6),
   'completado', pg_temp.uid('c2'), pg_temp.unidad('REP0002'), pg_temp.sitio('B'), 60,
   '2026-03-11 23:30-06', '2026-03-11 23:32-06', null);

-- c1 soltó el viaje bb02 antes de que se lo volvieran a asignar.
insert into public.viaje_eventos (viaje_id, estado_anterior, estado_nuevo, actor_id, ocurrido_en)
values ('00000000-0000-0000-0000-00000000bb02', 'asignado', 'buscando', pg_temp.uid('c1'), '2026-03-10 15:10-06');

-- Ofertas de c1: aceptada, rechazada, vencida, retirada (no vencida) y una fila "soltada".
insert into public.ofertas_viaje (viaje_id, conductor_id, respuesta, ofrecido_en, expira_en, respondido_en) values
  ('00000000-0000-0000-0000-00000000bb01', pg_temp.uid('c1'), 'aceptada',  '2026-03-10 18:01-06', '2026-03-10 18:01:20-06', '2026-03-10 18:01:10-06'),
  ('00000000-0000-0000-0000-00000000bb03', pg_temp.uid('c1'), 'rechazada', '2026-03-10 10:01-06', '2026-03-10 10:01:20-06', '2026-03-10 10:01:05-06'),
  ('00000000-0000-0000-0000-00000000bb04', pg_temp.uid('c1'), 'expirada',  '2026-03-11 09:01-06', '2026-03-11 09:01:20-06', '2026-03-11 09:01:24-06'),
  ('00000000-0000-0000-0000-00000000bb05', pg_temp.uid('c1'), 'expirada',  '2026-03-11 23:31-06', '2026-03-11 23:31:20-06', '2026-03-11 23:31:08-06'),
  ('00000000-0000-0000-0000-00000000bb02', pg_temp.uid('c1'), 'soltada',   '2026-03-10 15:10-06', '2026-03-10 15:10:20-06', '2026-03-10 15:10-06');

create function pg_temp.como(p text) returns void language plpgsql as $$
declare
  v_claims jsonb;
begin
  perform set_config('role', 'postgres', true);
  v_claims := public.custom_access_token_hook(jsonb_build_object(
    'user_id', pg_temp.uid(p),
    'claims', jsonb_build_object('sub', pg_temp.uid(p), 'role', 'authenticated')
  )) -> 'claims';
  perform set_config('request.jwt.claims', v_claims::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function pg_temp.error_de(p_sql text) returns text language plpgsql as $$
declare
  v_hint text;
begin
  execute p_sql;
  return null;
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  return coalesce(nullif(v_hint, ''), sqlstate);
end;
$$;

-- ── Por día (despacho central) ───────────────────────────────────────
select pg_temp.como('d0');

select is((select count(*) from public.reporte_por_dia('2026-03-10', '2026-03-12')), 3::bigint,
  'Un renglón por día, incluidos los días sin viajes');
select is(
  (select (solicitados, completados, cancelados, cancelados_pasajero, ingresos, a_convenir)::text
   from public.reporte_por_dia('2026-03-10', '2026-03-10')),
  '(3,2,1,1,45.00,1)',
  'Día 10: el viaje de las 6 p. m. cuenta en hora local, no en UTC');
select is((select minutos_asignacion from public.reporte_por_dia('2026-03-10', '2026-03-10')), 4.0,
  'Promedio de minutos para asignar (3 y 5 → 4)');
select is(
  (select (solicitados, sin_conductor, por_telefono, ingresos)::text
   from public.reporte_por_dia('2026-03-11', '2026-03-11')),
  '(2,1,1,60.00)',
  'Día 11: el viaje de las 11:30 p. m. cuenta ese día');
select is(
  (select (solicitados, ingresos)::text from public.reporte_por_dia('2026-03-12', '2026-03-12')),
  '(0,0)', 'Un día sin viajes sale en ceros');

-- ── Por conductor ────────────────────────────────────────────────────
select is(
  (select (completados, ingresos, a_convenir)::text from public.reporte_por_conductor('2026-03-10', '2026-03-11')
   where conductor_id = pg_temp.uid('c1')),
  '(2,45.00,1)', 'Conductor: viajes completados, ingresos y a convenir');
select is(
  (select (ofertas, aceptadas, rechazadas, vencidas, soltados)::text
   from public.reporte_por_conductor('2026-03-10', '2026-03-11') where conductor_id = pg_temp.uid('c1')),
  '(4,1,1,1,1)',
  'Ofertas: la retirada no es vencida y la fila "soltada" no cuenta como oferta');

-- ── Despacho de sitio: solo su sitio ─────────────────────────────────
select pg_temp.como('d1');
select is((select (solicitados, ingresos)::text from public.reporte_por_dia('2026-03-11', '2026-03-11')),
  '(1,0)', 'El despacho del sitio A no ve los viajes del sitio B');
select is((select count(*) from public.reporte_por_conductor('2026-03-10', '2026-03-11')), 2::bigint,
  'El despacho del sitio A solo ve a los conductores de su sitio');

-- ── Permisos y validación ────────────────────────────────────────────
select pg_temp.como('e1');
select is(pg_temp.error_de($$ select * from public.reporte_por_dia('2026-03-10', '2026-03-11') $$),
  '42501', 'Un pasajero no puede ver reportes');
select pg_temp.como('d0');
select is(pg_temp.error_de($$ select * from public.reporte_por_dia('2026-03-11', '2026-03-10') $$),
  'rango_invalido', 'Rango de fechas invertido es rechazado');
select is(pg_temp.error_de($$ select * from public.reporte_por_conductor('2025-01-01', '2026-03-10') $$),
  'rango_invalido', 'Más de un año es rechazado');

-- ── Soltar un viaje conserva la oferta aceptada ──────────────────────
reset role;
insert into public.conductor_estado (conductor_id, estado, unidad_id, ubicacion)
values (pg_temp.uid('c3'), 'disponible', pg_temp.unidad('REP0003'), public.punto(16.3291, -96.596));

select pg_temp.como('e2');
select public.solicitar_viaje('00000000-0000-0000-0000-00000000bb09', 16.329, -96.596);
select pg_temp.como('c3');
select public.responder_oferta((select oferta_id from public.mi_oferta_pendiente()), true);
select public.cancelar_viaje((select viaje_id from public.mi_viaje_activo_conductor()));
reset role;

select is(
  (select respuesta::text from public.ofertas_viaje
   where conductor_id = pg_temp.uid('c3')
     and viaje_id = (select id from public.viajes where client_request_id = '00000000-0000-0000-0000-00000000bb09')),
  'aceptada', 'Al soltar el viaje, su oferta sigue como aceptada (no se convierte en rechazo)');
select is(
  (select estado::text from public.viajes where client_request_id = '00000000-0000-0000-0000-00000000bb09'),
  'buscando', 'Y el viaje vuelve a buscar conductor');

select * from finish();
rollback;
