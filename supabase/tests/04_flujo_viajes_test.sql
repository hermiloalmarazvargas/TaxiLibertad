-- Pruebas del flujo de viajes: disponibilidad, solicitud, ofertas, avance,
-- cancelación, viajes telefónicos y asignación automática.
begin;
create extension if not exists pgtap with schema extensions;

select plan(54);

-- ── Usuarios: c1/c2 conductores · e1 pasajero · e2 pasajero (se bloqueará) · d0 despacho
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000004' || s)::uuid, s || '@viajes.local'
from unnest(array['c1', 'c2', 'e1', 'e2', 'd0']) as s;

create function pg_temp.uid(p text) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-0000000004' || p)::uuid $$;

-- Identificador de solicitud (client_request_id) por número.
create function pg_temp.req(n int) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $$;

insert into public.sitios (nombre) values ('Sitio Viajes');

insert into public.unidades (sitio_id, numero_economico, placas, marca, color)
select s.id, u.n, u.p, 'Tsuru', 'Blanco'
from public.sitios s, (values ('V-1', 'VIA0001'), ('V-2', 'VIA0002')) as u (n, p)
where s.nombre = 'Sitio Viajes';

create function pg_temp.unidad(p text) returns bigint language sql stable
as $$ select id from public.unidades where placas = p $$;

insert into public.perfiles (id, rol, nombre, usuario, telefono) values
  (pg_temp.uid('c1'), 'conductor',   'Chofer Uno',  'viajes.c1', null),
  (pg_temp.uid('c2'), 'conductor',   'Chofer Dos',  'viajes.c2', null),
  (pg_temp.uid('d0'), 'despachador', 'Despacho',    'viajes.d0', null),
  (pg_temp.uid('e1'), 'pasajero',    'Pasajera Uno', null, '+529518880001'),
  (pg_temp.uid('e2'), 'pasajero',    'Pasajero Dos', null, '+529518880002');

insert into public.conductores (perfil_id, sitio_id)
select pg_temp.uid(c), s.id from public.sitios s, unnest(array['c1', 'c2']) as c
where s.nombre = 'Sitio Viajes';

insert into public.conductor_estado (conductor_id)
values (pg_temp.uid('c1')), (pg_temp.uid('c2'));

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

-- Ejecuta SQL y devuelve el código de error (hint, o SQLSTATE si no hay hint).
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

-- Lecturas como postgres (sin RLS) para verificar el estado real.
create function pg_temp.viaje(n int) returns public.viajes language sql
security definer as $$ select * from public.viajes where client_request_id = pg_temp.req(n) $$;

create function pg_temp.estado_conductor(p text) returns public.conductor_estado language sql
as $$ select * from public.conductor_estado where conductor_id = pg_temp.uid(p) $$;

create function pg_temp.oferta_pendiente(n int) returns uuid language sql
as $$ select conductor_id from public.ofertas_viaje
      where viaje_id = (pg_temp.viaje(n)).id and respuesta = 'pendiente' $$;

-- Origen: centro de Miahuatlán. Destino: ~1.2 km al norte.
-- c1 está a ~55 m del origen; c2 a ~1 km.

-- =====================================================================
-- Disponibilidad
-- =====================================================================
select pg_temp.como('c1');
select is(pg_temp.error_de($$ select public.cambiar_disponibilidad('disponible') $$),
  'unidad_requerida', 'Disponible sin unidad: se pide elegir unidad');
select is((public.cambiar_disponibilidad('disponible', pg_temp.unidad('VIA0001'))).estado,
  'disponible'::public.estado_conductor, 'c1 se pone disponible con la unidad V-1');
update public.conductor_estado set ubicacion = public.punto(16.3295, -96.5960) where conductor_id = auth.uid();

select pg_temp.como('c2');
select is(pg_temp.error_de(format($$ select public.cambiar_disponibilidad('disponible', %s) $$, pg_temp.unidad('VIA0001'))),
  'unidad_ocupada', 'Una unidad en servicio no se puede tomar dos veces');
select is((public.cambiar_disponibilidad('disponible', pg_temp.unidad('VIA0002'))).unidad_id,
  pg_temp.unidad('VIA0002'), 'c2 se pone disponible con la unidad V-2');
update public.conductor_estado set ubicacion = public.punto(16.3380, -96.5960) where conductor_id = auth.uid();

reset role;
select ok((pg_temp.estado_conductor('c2')).ubicacion_en is not null,
  'El servidor pone la hora de la ubicación');

-- =====================================================================
-- Solicitud del pasajero
-- =====================================================================
select pg_temp.como('e1');
select is(
  (public.solicitar_viaje(pg_temp.req(1), 16.3290, -96.5960, 'Frente a la iglesia', 16.3400, -96.5960)).estado,
  'buscando'::public.estado_viaje, 'El pasajero pide un viaje');
select is(
  (public.solicitar_viaje(pg_temp.req(1), 16.3290, -96.5960, 'Frente a la iglesia', 16.3400, -96.5960)).id,
  (select id from public.viajes where client_request_id = pg_temp.req(1)),
  'Reintentar la misma solicitud devuelve el mismo viaje');
select is((select count(*) from public.viajes), 1::bigint, 'No se duplicó el viaje');
select is(pg_temp.error_de($$ select public.solicitar_viaje(pg_temp.req(2), 16.329, -96.596) $$),
  'viaje_activo', 'No se puede pedir otro viaje con uno activo');
select is(pg_temp.error_de($$ select public.solicitar_viaje(pg_temp.req(3), 95, -96.596) $$),
  'coordenadas_invalidas', 'Coordenadas fuera de rango son rechazadas');
select is((select count(*) from public.mi_viaje_activo()), 1::bigint, 'mi_viaje_activo devuelve el viaje');
select is(pg_temp.error_de($$ select public.mi_oferta_pendiente() $$),
  '42501', 'Un pasajero no puede consultar ofertas de conductor');

reset role;
select is((pg_temp.viaje(1)).tarifa_monto,
  (select monto from public.tarifa_estimada(16.3290, -96.5960, 16.3400, -96.5960)),
  'La tarifa se copia según las zonas');
select is((pg_temp.viaje(1)).origen_lat, 16.3290::double precision, 'Se expone la latitud del origen');
select is(pg_temp.oferta_pendiente(1), pg_temp.uid('c1'), 'El viaje se ofrece primero al conductor más cercano');

-- Pasajero bloqueado con token aún vigente: el bloqueo aplica de inmediato.
select pg_temp.como('e2');
reset role;
insert into public.telefonos_bloqueados (telefono, motivo) values ('+529518880002', 'Pedidos falsos');
set local role authenticated;
select is(pg_temp.error_de($$ select public.solicitar_viaje(pg_temp.req(4), 16.329, -96.596) $$),
  'telefono_bloqueado', 'Un número bloqueado no puede pedir aunque su token siga vigente');

-- =====================================================================
-- Ofertas
-- =====================================================================
select pg_temp.como('c1');
select ok((select segundos_restantes between 1 and 20 from public.mi_oferta_pendiente()),
  'La oferta trae los segundos restantes calculados en el servidor');
select is((select origen_referencia from public.mi_oferta_pendiente()), 'Frente a la iglesia',
  'La oferta muestra la referencia del origen');
select is((public.responder_oferta((select oferta_id from public.mi_oferta_pendiente()), false)).estado,
  'buscando'::public.estado_viaje, 'c1 rechaza la oferta');

reset role;
select is(pg_temp.oferta_pendiente(1), pg_temp.uid('c2'), 'Al rechazar, pasa al siguiente conductor');

-- La oferta de c2 vence sin respuesta.
update public.ofertas_viaje set expira_en = now() - interval '1 second'
where viaje_id = (pg_temp.viaje(1)).id and respuesta = 'pendiente';
select is(privado.procesar_ofertas_vencidas(), 0, 'El cron vence la oferta y no hay más candidatos');
select is((pg_temp.viaje(1)).estado, 'buscando'::public.estado_viaje,
  'Sigue buscando (aún no pasan 5 minutos)');

select pg_temp.como('c2');
select is(pg_temp.error_de(format($$ select public.responder_oferta(%s, true) $$,
    (select id from public.ofertas_viaje where conductor_id = auth.uid()))),
  'oferta_vencida', 'No se puede aceptar una oferta vencida');

-- =====================================================================
-- Asignación por despacho y avance del viaje
-- =====================================================================
select pg_temp.como('c1');
select is(pg_temp.error_de(format($$ select public.asignar_viaje(%L, %L) $$, (pg_temp.viaje(1)).id, pg_temp.uid('c1'))),
  '42501', 'Un conductor no puede asignar viajes');

select pg_temp.como('d0');
select is((public.asignar_viaje((pg_temp.viaje(1)).id, pg_temp.uid('c1'))).estado,
  'asignado'::public.estado_viaje, 'El despacho asigna el viaje directamente a c1');

reset role;
select is((pg_temp.estado_conductor('c1')).estado, 'ocupado'::public.estado_conductor,
  'El conductor asignado queda ocupado');
select is((pg_temp.viaje(1)).unidad_id, pg_temp.unidad('VIA0001'), 'El viaje guarda la unidad del conductor');

select pg_temp.como('e1');
select is((select unidad_placas from public.mi_viaje_activo()), 'VIA0001',
  'El pasajero ve las placas del taxi asignado');
select is((select conductor_nombre from public.mi_viaje_activo()), 'Chofer Uno',
  'El pasajero ve el nombre del conductor');

select pg_temp.como('c1');
select is((select pasajero_telefono from public.mi_viaje_activo_conductor()), '+529518880001',
  'El conductor ve el teléfono del pasajero durante el viaje');
select is(pg_temp.error_de($$ select public.cambiar_disponibilidad('fuera_de_servicio') $$),
  'viaje_en_curso', 'No puede salir de servicio con un viaje activo');
select is(pg_temp.error_de(format($$ select public.avanzar_viaje(%L, 'completado') $$, (pg_temp.viaje(1)).id)),
  'transicion_invalida', 'No puede terminar un viaje que no ha iniciado');
select is((public.avanzar_viaje((pg_temp.viaje(1)).id, 'conductor_llego')).estado,
  'conductor_llego'::public.estado_viaje, 'Llegué');
select is((public.avanzar_viaje((pg_temp.viaje(1)).id, 'conductor_llego')).estado,
  'conductor_llego'::public.estado_viaje, 'Repetir "Llegué" (reintento) no falla');
select ok((public.avanzar_viaje((pg_temp.viaje(1)).id, 'en_curso', now() + interval '1 hour')).iniciado_en <= now(),
  'Inicié viaje: una hora futura del teléfono se acota a la hora del servidor');

select pg_temp.como('e1');
select is(pg_temp.error_de(format($$ select public.cancelar_viaje(%L) $$, (pg_temp.viaje(1)).id)),
  'no_cancelable', 'El pasajero no puede cancelar un viaje en curso');

select pg_temp.como('c2');
select is(pg_temp.error_de(format($$ select public.avanzar_viaje(%L, 'completado') $$, (pg_temp.viaje(1)).id)),
  'viaje_no_encontrado', 'Otro conductor no puede mover el viaje');

select pg_temp.como('c1');
select is((public.avanzar_viaje((pg_temp.viaje(1)).id, 'completado')).estado,
  'completado'::public.estado_viaje, 'Terminé viaje');
select is((public.avanzar_viaje((pg_temp.viaje(1)).id, 'en_curso')).estado,
  'completado'::public.estado_viaje, 'Un paso viejo que llega tarde (sin señal) no retrocede el viaje');

reset role;
select is((pg_temp.estado_conductor('c1')).estado, 'disponible'::public.estado_conductor,
  'Al terminar, el conductor vuelve a estar disponible');
select is(
  (select array_agg(estado_nuevo::text order by id) from public.viaje_eventos where viaje_id = (pg_temp.viaje(1)).id),
  array['buscando', 'asignado', 'conductor_llego', 'en_curso', 'completado'],
  'La bitácora registra cada paso');

-- =====================================================================
-- Cancelaciones
-- =====================================================================
select pg_temp.como('e1');
select public.solicitar_viaje(pg_temp.req(5), 16.3290, -96.5960);

select pg_temp.como('c1');
select is((public.responder_oferta((select oferta_id from public.mi_oferta_pendiente()), true)).estado,
  'asignado'::public.estado_viaje, 'c1 acepta la oferta');
select is((public.cancelar_viaje((pg_temp.viaje(5)).id, 'Se ponchó una llanta')).estado,
  'buscando'::public.estado_viaje, 'El conductor suelta el viaje: vuelve a buscar');

reset role;
select is(pg_temp.oferta_pendiente(5), pg_temp.uid('c2'),
  'El viaje soltado se ofrece a otro conductor, no al que lo soltó');

select pg_temp.como('e1');
select is((public.cancelar_viaje((pg_temp.viaje(5)).id, 'Ya no lo necesito')).estado,
  'cancelado'::public.estado_viaje, 'El pasajero cancela');
select is((public.cancelar_viaje((pg_temp.viaje(5)).id)).estado,
  'cancelado'::public.estado_viaje, 'Cancelar dos veces no falla');

reset role;
select is((select count(*) from public.ofertas_viaje where respuesta = 'pendiente'), 0::bigint,
  'Al cancelar se retira la oferta pendiente');

-- =====================================================================
-- Viajes por teléfono
-- =====================================================================
select pg_temp.como('e1');
select is(pg_temp.error_de($$ select public.crear_viaje_telefonico(pg_temp.req(6), 'X', '9510000000', 16.329, -96.596) $$),
  '42501', 'Un pasajero no puede crear viajes telefónicos');

select pg_temp.como('d0');
select is(
  (public.crear_viaje_telefonico(pg_temp.req(7), 'Doña Rosa', '951 555 0000', 16.3290, -96.5960,
     'Tienda azul junto al molino', null, null, null, pg_temp.uid('c2'))).estado,
  'asignado'::public.estado_viaje, 'Viaje telefónico asignado directamente');
select is(pg_temp.error_de($$ select public.crear_viaje_telefonico(pg_temp.req(8), 'X', '951 888 0002', 16.329, -96.596) $$),
  'telefono_bloqueado', 'No se crean viajes para números bloqueados');

reset role;
select is((pg_temp.viaje(7)).contacto_telefono::text, '+529515550000', 'El teléfono de contacto se normaliza');
select is((pg_temp.viaje(7)).tarifa_monto, null::numeric, 'Sin destino: tarifa a convenir');

-- =====================================================================
-- Sin conductor y fuera de servicio
-- =====================================================================
select pg_temp.como('c1');
select ok((public.cambiar_disponibilidad('fuera_de_servicio')).ubicacion is null,
  'Fuera de servicio se borra la ubicación');

select pg_temp.como('e1');
select public.solicitar_viaje(pg_temp.req(9), 16.3290, -96.5960);
reset role;
update public.viajes set solicitado_en = now() - interval '6 minutes' where id = (pg_temp.viaje(9)).id;
select privado.procesar_ofertas_vencidas();
select is((pg_temp.viaje(9)).estado, 'sin_conductor'::public.estado_viaje,
  'Tras 5 minutos sin conductores el viaje queda "sin conductor"');

select * from finish();
rollback;
