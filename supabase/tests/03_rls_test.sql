-- Pruebas de permisos y RLS: cada bloque se hace pasar por un usuario distinto.
begin;
create extension if not exists pgtap with schema extensions;

select plan(39);

-- ── Usuarios de prueba ───────────────────────────────────────────────
--   a0 admin · d0 despacho central · d1 despacho sitio A
--   c1 conductor A (en viaje) · c2 conductor A (fuera de servicio) · c3 conductor B
--   e1 / e2 pasajeros · f0 sesión anónima sin registrar
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000000' || s)::uuid, s || '@rls.local'
from unnest(array['a0', 'd0', 'd1', 'c1', 'c2', 'c3', 'e1', 'e2', 'f0']) as s;

insert into public.sitios (nombre) values ('RLS Sitio A'), ('RLS Sitio B');

create function pg_temp.uid(p text) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-0000000000' || p)::uuid $$;

create function pg_temp.sitio(p text) returns bigint language sql stable
as $$ select id from public.sitios where nombre = 'RLS Sitio ' || p $$;

create function pg_temp.unidad(p text) returns bigint language sql stable
as $$ select id from public.unidades where placas = p $$;

insert into public.perfiles (id, rol, nombre, usuario, telefono, sitio_id) values
  (pg_temp.uid('a0'), 'admin',       'Admin',          'rls.admin', null, null),
  (pg_temp.uid('d0'), 'despachador', 'Despacho Central', 'rls.d0',  null, null),
  (pg_temp.uid('d1'), 'despachador', 'Despacho A',     'rls.d1',    null, pg_temp.sitio('A')),
  (pg_temp.uid('c1'), 'conductor',   'Conductor A1',   'rls.c1',    null, null),
  (pg_temp.uid('c2'), 'conductor',   'Conductor A2',   'rls.c2',    null, null),
  (pg_temp.uid('c3'), 'conductor',   'Conductor B1',   'rls.c3',    null, null),
  (pg_temp.uid('e1'), 'pasajero',    'Pasajero Uno',   null, '+529517770001', null),
  (pg_temp.uid('e2'), 'pasajero',    'Pasajero Dos',   null, '+529517770002', null);

insert into public.unidades (sitio_id, numero_economico, placas) values
  (pg_temp.sitio('A'), 'A-1', 'RLS0001'),
  (pg_temp.sitio('A'), 'A-2', 'RLS0002'),
  (pg_temp.sitio('B'), 'B-1', 'RLS0003');

insert into public.conductores (perfil_id, sitio_id) values
  (pg_temp.uid('c1'), pg_temp.sitio('A')),
  (pg_temp.uid('c2'), pg_temp.sitio('A')),
  (pg_temp.uid('c3'), pg_temp.sitio('B'));

insert into public.conductor_estado (conductor_id, estado, unidad_id) values
  (pg_temp.uid('c1'), 'ocupado',           pg_temp.unidad('RLS0001')),
  (pg_temp.uid('c2'), 'fuera_de_servicio', null),
  (pg_temp.uid('c3'), 'disponible',        pg_temp.unidad('RLS0003'));

-- v1: e1 buscando (sin sitio) · v2: e1 asignado a c1 (sitio A) · v3: e2 completado con c3 (sitio B)
insert into public.viajes (id, canal, pasajero_id, origen, estado, sitio_id, conductor_id, unidad_id) values
  ('00000000-0000-0000-0000-00000000aa01', 'app', pg_temp.uid('e1'), public.punto(16.329, -96.596),
   'buscando', null, null, null),
  ('00000000-0000-0000-0000-00000000aa02', 'app', pg_temp.uid('e1'), public.punto(16.329, -96.596),
   'asignado', pg_temp.sitio('A'), pg_temp.uid('c1'), pg_temp.unidad('RLS0001')),
  ('00000000-0000-0000-0000-00000000aa03', 'app', pg_temp.uid('e2'), public.punto(16.329, -96.596),
   'completado', pg_temp.sitio('B'), pg_temp.uid('c3'), pg_temp.unidad('RLS0003'));

insert into public.viaje_eventos (viaje_id, estado_nuevo)
select id, estado from public.viajes where id::text like '00000000-0000-0000-0000-00000000aa0%';

insert into public.ofertas_viaje (viaje_id, conductor_id)
values ('00000000-0000-0000-0000-00000000aa01', pg_temp.uid('c3'));

-- Se hace pasar por un usuario: genera sus claims con el hook REAL.
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

create function pg_temp.cuantos(p_tabla text) returns bigint language plpgsql as $$
declare v bigint;
begin
  execute format('select count(*) from public.%I', p_tabla) into v;
  return v;
end;
$$;

-- ── Pasajero e1 ──────────────────────────────────────────────────────
select pg_temp.como('e1');
select is(pg_temp.cuantos('viajes'), 2::bigint, 'Pasajero: ve solo sus 2 viajes');
select is(pg_temp.cuantos('viaje_eventos'), 2::bigint, 'Pasajero: ve la bitácora solo de sus viajes');
select is(pg_temp.cuantos('conductor_estado'), 1::bigint, 'Pasajero: ve solo al conductor de su viaje activo');
select is(pg_temp.cuantos('unidades'), 1::bigint, 'Pasajero: ve solo la unidad de su viaje activo');
select is(pg_temp.cuantos('perfiles'), 1::bigint, 'Pasajero: ve solo su perfil');
select is(pg_temp.cuantos('telefonos_bloqueados'), 0::bigint, 'Pasajero: no ve números bloqueados');
select ok(pg_temp.cuantos('zonas') > 0, 'Pasajero: ve las zonas (para la tarifa estimada)');
select throws_ok(
  $$ insert into public.zonas (nombre, poligono) values ('Hack', extensions.st_multi(extensions.st_geomfromtext('POLYGON((0 0,1 0,1 1,0 1,0 0))', 4326))) $$,
  '42501', null, 'Pasajero: no puede crear zonas');
select throws_ok(
  $$ update public.viajes set estado = 'completado' $$,
  '42501', null, 'Pasajero: no puede cambiar el estado de un viaje directamente');
-- Intento silencioso (RLS filtra filas, no lanza error): se verifica más abajo.
update public.conductor_estado set precision_m = 999;

-- ── Conductor c1 (sitio A, en viaje) ────────────────────────────────
select pg_temp.como('c1');
select is(pg_temp.cuantos('viajes'), 1::bigint, 'Conductor: ve solo su viaje asignado');
select is(pg_temp.cuantos('unidades'), 2::bigint, 'Conductor: ve las unidades activas de su sitio');
select is(pg_temp.cuantos('perfiles'), 1::bigint, 'Conductor: ve solo su perfil');
select is(pg_temp.cuantos('ofertas_viaje'), 0::bigint, 'Conductor: no ve ofertas de otros');
select lives_ok(
  $$ update public.conductor_estado
     set ubicacion = public.punto(16.33, -96.59), rumbo = 10, ubicacion_en = now()
     where conductor_id = auth.uid() $$,
  'Conductor: reporta su ubicación');
select throws_ok(
  $$ update public.conductor_estado set estado = 'disponible' where conductor_id = auth.uid() $$,
  '42501', null, 'Conductor: no cambia su estado directamente (será por RPC)');
update public.conductor_estado set ubicacion = public.punto(0, 0)
where conductor_id = pg_temp.uid('c3');

-- ── Conductor c2 (fuera de servicio) ────────────────────────────────
select pg_temp.como('c2');
update public.conductor_estado set ubicacion = public.punto(0, 0) where conductor_id = auth.uid();

-- ── Conductor c3 (sitio B) ──────────────────────────────────────────
select pg_temp.como('c3');
select is(pg_temp.cuantos('ofertas_viaje'), 1::bigint, 'Conductor: ve su oferta pendiente');
select is(pg_temp.cuantos('viajes'), 1::bigint, 'Conductor: una oferta no le da acceso a la fila del viaje');

-- ── Despachador del sitio A ─────────────────────────────────────────
select pg_temp.como('d1');
select is(pg_temp.cuantos('viajes'), 2::bigint, 'Despacho de sitio: ve viajes de su sitio y los que buscan conductor');
select is(pg_temp.cuantos('conductores'), 2::bigint, 'Despacho de sitio: ve solo conductores de su sitio');
select is(pg_temp.cuantos('conductor_estado'), 2::bigint, 'Despacho de sitio: ve estado solo de su sitio');
select is(pg_temp.cuantos('unidades'), 2::bigint, 'Despacho de sitio: ve solo unidades de su sitio');
select lives_ok(
  $$ insert into public.telefonos_bloqueados (telefono, motivo) values ('+529517770009', 'Pedido falso') $$,
  'Despacho: puede bloquear un número');
select throws_ok(
  $$ insert into public.telefonos_bloqueados (telefono, motivo, bloqueado_por)
     values ('+529517770008', 'Falso', '00000000-0000-0000-0000-0000000000a0') $$,
  '42501', null, 'Despacho: no puede bloquear a nombre de otro');
select throws_ok(
  $$ insert into public.zonas (nombre, poligono) values ('Hack', extensions.st_multi(extensions.st_geomfromtext('POLYGON((0 0,1 0,1 1,0 1,0 0))', 4326))) $$,
  '42501', null, 'Despacho: no puede crear zonas');

-- ── Despacho central ────────────────────────────────────────────────
select pg_temp.como('d0');
select is(pg_temp.cuantos('viajes'), 3::bigint, 'Despacho central: ve todos los viajes');
select is(pg_temp.cuantos('conductor_estado'), 3::bigint, 'Despacho central: ve a todos los conductores');

-- ── Admin ───────────────────────────────────────────────────────────
select pg_temp.como('a0');
select lives_ok(
  $$ insert into public.zonas (nombre, poligono) values ('RLS Zona', extensions.st_multi(extensions.st_geomfromtext('POLYGON((0 0,1 0,1 1,0 1,0 0))', 4326))) $$,
  'Admin: puede crear zonas');
select lives_ok(
  $$ update public.perfiles set activo = false where id = '00000000-0000-0000-0000-0000000000e2' $$,
  'Admin: puede desactivar un perfil');
select throws_ok(
  $$ update public.perfiles set rol = 'admin' where id = '00000000-0000-0000-0000-0000000000e1' $$,
  '42501', null, 'Admin: ni siquiera el admin cambia roles por la API');

-- ── Sesión anónima sin registrar ────────────────────────────────────
select pg_temp.como('f0');
select is(pg_temp.cuantos('zonas'), 0::bigint, 'Sin registrar: no ve zonas');
select is(pg_temp.cuantos('viajes'), 0::bigint, 'Sin registrar: no ve viajes');

-- ── anon (sin sesión) ───────────────────────────────────────────────
select set_config('role', 'anon', true);
select throws_ok($$ select count(*) from public.zonas $$, '42501', null, 'anon: sin acceso a tablas');
select throws_ok($$ select * from public.tarifa_estimada(16.3, -96.5) $$, '42501', null, 'anon: sin acceso a funciones');

-- ── Verificaciones como postgres ────────────────────────────────────
reset role;

select ok(
  (select ubicacion is not null from public.conductor_estado where conductor_id = pg_temp.uid('c1')),
  'La ubicación de c1 sí se guardó');
select ok(
  (select precision_m is null from public.conductor_estado where conductor_id = pg_temp.uid('c1')),
  'El pasajero no pudo modificar el estado del conductor');
select ok(
  (select ubicacion is null from public.conductor_estado where conductor_id = pg_temp.uid('c3')),
  'Un conductor no puede modificar la ubicación de otro');
select ok(
  (select ubicacion is null from public.conductor_estado where conductor_id = pg_temp.uid('c2')),
  'Fuera de servicio no se puede reportar ubicación');
select is(
  (select bloqueado_por from public.telefonos_bloqueados where telefono = '+529517770009'),
  pg_temp.uid('d1'),
  'El bloqueo registra quién lo hizo');
select is(
  (public.custom_access_token_hook(jsonb_build_object(
    'user_id', pg_temp.uid('c1'), 'claims', '{}'::jsonb)) -> 'claims' ->> 'sitio_id')::bigint,
  pg_temp.sitio('A'),
  'El token del conductor lleva el sitio de su registro de conductor');

select * from finish();
rollback;
