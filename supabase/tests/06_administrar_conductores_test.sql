-- Pruebas: desactivar y reactivar conductores.
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000006' || s)::uuid, s || '@admcond.local'
from unnest(array['a0', 'd0', 'c1', 'c2', 'c3', 'e1']) as s;

create function pg_temp.uid(p text) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-0000000006' || p)::uuid $$;

insert into public.sitios (nombre) values ('Sitio AdmCond');
insert into public.unidades (sitio_id, numero_economico, placas)
select s.id, u.n, u.p from public.sitios s,
  (values ('AC-1', 'ADC0001'), ('AC-2', 'ADC0002'), ('AC-3', 'ADC0003')) as u (n, p)
where s.nombre = 'Sitio AdmCond';

insert into public.perfiles (id, rol, nombre, usuario, telefono) values
  (pg_temp.uid('a0'), 'admin',       'Admin',    'adc.a0', null),
  (pg_temp.uid('d0'), 'despachador', 'Despacho', 'adc.d0', null),
  (pg_temp.uid('c1'), 'conductor',   'Chofer 1', 'adc.c1', null),
  (pg_temp.uid('c2'), 'conductor',   'Chofer 2', 'adc.c2', null),
  (pg_temp.uid('c3'), 'conductor',   'Chofer 3', 'adc.c3', null),
  (pg_temp.uid('e1'), 'pasajero',    'Pasajero', null, '+529513330001');

insert into public.conductores (perfil_id, sitio_id)
select pg_temp.uid(c), s.id from public.sitios s, unnest(array['c1', 'c2', 'c3']) as c
where s.nombre = 'Sitio AdmCond';

-- c1 a 50 m del origen, c2 a 1 km: el viaje se ofrece primero a c1.
insert into public.conductor_estado (conductor_id, estado, unidad_id, ubicacion)
select pg_temp.uid(v.c), 'disponible', u.id, public.punto(v.lat, -96.596)
from (values ('c1', 'ADC0001', 16.3295), ('c2', 'ADC0002', 16.338)) as v (c, placas, lat)
join public.unidades u on u.placas = v.placas;
insert into public.conductor_estado (conductor_id) values (pg_temp.uid('c3'));

-- Token "vigente": claims armados a mano (el hook real ya no se los daría
-- a una cuenta desactivada, pero un token emitido antes sigue sirviendo ~1 h).
create function pg_temp.con_token(p text, p_rol text) returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', pg_temp.uid(p), 'role', 'authenticated', 'rol', p_rol)::text, true);
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

-- Lee como postgres (el token de prueba no trae sitio_id para RLS).
create function pg_temp.unidad(p text) returns bigint language sql security definer
as $$ select id from public.unidades where placas = p $$;

create function pg_temp.estado(p text) returns public.conductor_estado language sql
as $$ select * from public.conductor_estado where conductor_id = pg_temp.uid(p) $$;

-- El pasajero pide un viaje → se ofrece a c1.
select pg_temp.con_token('e1', 'pasajero');
select public.solicitar_viaje('00000000-0000-0000-0000-000000000601', 16.329, -96.596);
reset role;

-- ── Permisos ─────────────────────────────────────────────────────────
select pg_temp.con_token('d0', 'despachador');
select is(pg_temp.error_de(format($$ select public.cambiar_activo_conductor(%L, false) $$, pg_temp.uid('c1'))),
  '42501', 'Un despachador no puede desactivar conductores');

-- ── Desactivar a c1 (disponible, viendo una oferta) ─────────────────
select pg_temp.con_token('a0', 'admin');
select lives_ok(format($$ select public.cambiar_activo_conductor(%L, false) $$, pg_temp.uid('c1')),
  'El admin desactiva a un conductor disponible');
reset role;

select is((pg_temp.estado('c1')).estado, 'fuera_de_servicio'::public.estado_conductor,
  'Queda fuera de servicio');
select is((pg_temp.estado('c1')).motivo_fuera, 'desactivado', 'Con motivo "desactivado"');
select ok((pg_temp.estado('c1')).unidad_id is null, 'Libera su unidad');
select is(
  (select conductor_id from public.ofertas_viaje where respuesta = 'pendiente'
     and viaje_id = (select id from public.viajes where client_request_id = '00000000-0000-0000-0000-000000000601')),
  pg_temp.uid('c2'),
  'Su oferta pendiente pasa al siguiente conductor');
select is((pg_temp.estado('c1')).ofertas_vencidas_seguidas, 0::smallint,
  'La oferta retirada por desactivación no cuenta como ignorada');

-- Con su token todavía vigente, ya no puede actuar.
select pg_temp.con_token('c1', 'conductor');
select is(pg_temp.error_de(format($$ select public.cambiar_disponibilidad('disponible', %s) $$,
    pg_temp.unidad('ADC0001'))),
  '42501', 'Con el token aún vigente, un conductor desactivado no puede ponerse disponible');

-- ── No se puede desactivar con viaje en curso ───────────────────────
select pg_temp.con_token('c2', 'conductor');
select public.responder_oferta((select oferta_id from public.mi_oferta_pendiente()), true);
select pg_temp.con_token('a0', 'admin');
select is(pg_temp.error_de(format($$ select public.cambiar_activo_conductor(%L, false) $$, pg_temp.uid('c2'))),
  'viaje_en_curso', 'No se puede desactivar a un conductor con viaje en curso');

-- ── Desactivar a c3 (ya fuera de servicio) y reactivar a c1 ────────
select public.cambiar_activo_conductor(pg_temp.uid('c3'), false);
select public.cambiar_activo_conductor(pg_temp.uid('c1'), true);
reset role;

select is((pg_temp.estado('c3')).motivo_fuera, 'desactivado',
  'Desactivar a alguien fuera de servicio actualiza el motivo');
select ok(
  (select p.activo and c.activo from public.perfiles p join public.conductores c on c.perfil_id = p.id
   where p.id = pg_temp.uid('c1')),
  'Al reactivar, el perfil y el registro de conductor quedan activos');

select pg_temp.con_token('c1', 'conductor');
select is((public.cambiar_disponibilidad('disponible', pg_temp.unidad('ADC0001'))).estado,
  'disponible'::public.estado_conductor, 'Reactivado, puede volver a ponerse disponible');

select * from finish();
rollback;
