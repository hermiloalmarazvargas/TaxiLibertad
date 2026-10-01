-- Pruebas: 3 ofertas vencidas seguidas → fuera de servicio + notificación.
begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000005' || s)::uuid, s || '@ignoradas.local'
from unnest(array['c1', 'e1', 'd0']) as s;

create function pg_temp.uid(p text) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-0000000005' || p)::uuid $$;

insert into public.sitios (nombre) values ('Sitio Ignoradas');
insert into public.unidades (sitio_id, numero_economico, placas)
select id, 'I-1', 'IGN0001' from public.sitios where nombre = 'Sitio Ignoradas';

insert into public.perfiles (id, rol, nombre, usuario, telefono) values
  (pg_temp.uid('c1'), 'conductor',   'Chofer',   'ign.c1', null),
  (pg_temp.uid('d0'), 'despachador', 'Despacho', 'ign.d0', null),
  (pg_temp.uid('e1'), 'pasajero',    'Pasajero', null, '+529516660001');

insert into public.conductores (perfil_id, sitio_id)
select pg_temp.uid('c1'), id from public.sitios where nombre = 'Sitio Ignoradas';

insert into public.conductor_estado (conductor_id, estado, unidad_id, ubicacion)
select pg_temp.uid('c1'), 'disponible', id, public.punto(16.3291, -96.5960)
from public.unidades where placas = 'IGN0001';

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

create function pg_temp.estado() returns public.conductor_estado language sql
as $$ select * from public.conductor_estado where conductor_id = pg_temp.uid('c1') $$;

-- Crea un viaje para que se le ofrezca a c1 (el único conductor) y lo
-- deja vencer o lo rechaza. Cada viaje es nuevo porque a quien ya vio un
-- viaje no se le vuelve a ofrecer.
create function pg_temp.nueva_oferta(n int) returns void language plpgsql as $$
begin
  perform pg_temp.como('e1');
  perform public.solicitar_viaje(('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 16.329, -96.596);
  perform set_config('role', 'postgres', true);
end;
$$;

create function pg_temp.dejar_vencer() returns void language plpgsql as $$
begin
  update public.ofertas_viaje set expira_en = now() - interval '1 second' where respuesta = 'pendiente';
  perform privado.procesar_ofertas_vencidas();
  -- Cerrar el viaje para que el pasajero pueda pedir otro.
  update public.viajes set estado = 'cancelado' where estado = 'buscando';
end;
$$;

-- ── 2 vencidas ───────────────────────────────────────────────────────
select pg_temp.nueva_oferta(1); select pg_temp.dejar_vencer();
select pg_temp.nueva_oferta(2); select pg_temp.dejar_vencer();
select is((pg_temp.estado()).ofertas_vencidas_seguidas, 2::smallint, 'Dos ofertas vencidas se cuentan');
select is((pg_temp.estado()).estado, 'disponible'::public.estado_conductor, 'Con 2 sigue disponible');

-- ── Rechazar reinicia la cuenta ──────────────────────────────────────
select pg_temp.nueva_oferta(3);
select pg_temp.como('c1');
select public.responder_oferta((select oferta_id from public.mi_oferta_pendiente()), false);
reset role;
update public.viajes set estado = 'cancelado' where estado = 'buscando';
select is((pg_temp.estado()).ofertas_vencidas_seguidas, 0::smallint, 'Rechazar no cuenta y reinicia la cuenta');

-- ── Una oferta retirada antes de vencer no cuenta ────────────────────
select pg_temp.nueva_oferta(4);
select pg_temp.como('e1');
select public.cancelar_viaje((select id from public.viajes where estado = 'buscando'));
reset role;
select is((pg_temp.estado()).ofertas_vencidas_seguidas, 0::smallint,
  'Si el pasajero cancela antes de que venza, no cuenta');

-- ── 3 vencidas seguidas ──────────────────────────────────────────────
select pg_temp.nueva_oferta(5); select pg_temp.dejar_vencer();
select pg_temp.nueva_oferta(6); select pg_temp.dejar_vencer();
select is((select count(*) from public.notificaciones), 0::bigint, 'Sin notificación antes de la tercera');
select pg_temp.nueva_oferta(7); select pg_temp.dejar_vencer();

select is((pg_temp.estado()).estado, 'fuera_de_servicio'::public.estado_conductor,
  'A la tercera vencida pasa a fuera de servicio');
select is((pg_temp.estado()).motivo_fuera, 'sin_respuesta', 'Con motivo "sin_respuesta"');
select ok((pg_temp.estado()).ubicacion is null and (pg_temp.estado()).unidad_id is null,
  'Se libera la unidad y se borra la ubicación');
select is((select tipo from public.notificaciones where perfil_id = pg_temp.uid('c1')),
  'fuera_por_no_responder', 'Se le crea una notificación explicando el motivo');

-- ── Visibilidad ──────────────────────────────────────────────────────
select pg_temp.como('d0');
select is((select motivo_fuera from public.conductor_estado where conductor_id = pg_temp.uid('c1')),
  'sin_respuesta', 'El despacho ve que quedó fuera por no responder');
select is((select count(*) from public.notificaciones), 0::bigint, 'El despacho no ve notificaciones ajenas');

select pg_temp.como('c1');
select is((select count(*) from public.notificaciones), 1::bigint, 'El conductor ve su notificación');

-- ── Volver a estar disponible ────────────────────────────────────────
select public.cambiar_disponibilidad('disponible', (select id from public.unidades where placas = 'IGN0001'));
reset role;
select ok((pg_temp.estado()).ofertas_vencidas_seguidas = 0 and (pg_temp.estado()).motivo_fuera is null,
  'Al volver a disponible se reinicia la cuenta y el motivo');

select pg_temp.como('c1');
select public.cambiar_disponibilidad('fuera_de_servicio');
reset role;
select is((pg_temp.estado()).motivo_fuera, 'manual', 'Salir de servicio por cuenta propia queda como "manual"');

select * from finish();
rollback;
