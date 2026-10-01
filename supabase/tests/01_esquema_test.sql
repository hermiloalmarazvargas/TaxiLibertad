-- Pruebas del esquema base. Se ejecutan con: npx supabase test db
-- Todo corre dentro de una transacción que se revierte al final; no usa el seed.
begin;
create extension if not exists pgtap with schema extensions;

select plan(10);

-- ── Datos propios de la prueba (lejos de Miahuatlán, en lat/lng 0..1) ──
insert into public.zonas (nombre, poligono) values
  ('Prueba A', extensions.st_multi(extensions.st_geomfromtext('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 4326))),
  ('Prueba B', extensions.st_multi(extensions.st_geomfromtext('POLYGON((1 0, 2 0, 2 1, 1 1, 1 0))', 4326))),
  -- Zona pequeña dentro de A: debe ganar por ser más específica.
  ('Prueba A chica', extensions.st_multi(extensions.st_geomfromtext('POLYGON((0.1 0.1, 0.2 0.1, 0.2 0.2, 0.1 0.2, 0.1 0.1))', 4326)));

insert into public.tarifas (zona_origen_id, zona_destino_id, monto)
select a.id, b.id, 50 from public.zonas a, public.zonas b
where a.nombre = 'Prueba A' and b.nombre = 'Prueba B';

-- ── Tarifas ──
select is(
  (select monto from public.tarifa_estimada(0.5, 0.5, 0.5, 1.5)),
  50::numeric,
  'A→B usa la tarifa capturada'
);

select is(
  (select monto from public.tarifa_estimada(0.5, 1.5, 0.5, 0.5)),
  null::numeric,
  'B→A sin tarifa capturada = a convenir (las direcciones son independientes)'
);

select is(
  (select zona_origen from public.tarifa_estimada(0.5, 0.5)),
  'Prueba A',
  'Sin destino: se detecta la zona de origen'
);

select is(
  (select monto from public.tarifa_estimada(0.5, 0.5)),
  null::numeric,
  'Sin destino = a convenir'
);

select is(
  (select zona_origen_id from public.tarifa_estimada(5, 5, 0.5, 0.5)),
  null::bigint,
  'Origen fuera de todas las zonas = sin zona'
);

select is(
  (select zona_origen from public.tarifa_estimada(0.15, 0.15)),
  'Prueba A chica',
  'En zonas traslapadas gana la de menor área'
);

-- ── Restricciones ──
insert into public.sitios (nombre) values ('Sitio Prueba');
insert into public.unidades (sitio_id, numero_economico, placas)
select id, 'P-01', 'PRB0001' from public.sitios where nombre = 'Sitio Prueba';

select throws_ok(
  $$ insert into public.unidades (sitio_id, numero_economico, placas)
     select id, 'P-02', 'PRB0001' from public.sitios where nombre = 'Sitio Prueba' $$,
  '23505', null,
  'No se permiten placas duplicadas'
);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'c1@prueba.local'),
  ('00000000-0000-0000-0000-0000000000c2', 'c2@prueba.local'),
  ('00000000-0000-0000-0000-0000000000a1', 'p1@prueba.local');

insert into public.perfiles (id, rol, nombre, usuario) values
  ('00000000-0000-0000-0000-0000000000c1', 'conductor', 'Conductor Uno', 'prueba.c1'),
  ('00000000-0000-0000-0000-0000000000c2', 'conductor', 'Conductor Dos', 'prueba.c2');

insert into public.conductores (perfil_id, sitio_id)
select p.id, s.id
from public.perfiles p, public.sitios s
where p.rol = 'conductor' and s.nombre = 'Sitio Prueba';

insert into public.conductor_estado (conductor_id, estado, unidad_id)
select '00000000-0000-0000-0000-0000000000c1', 'disponible', id
from public.unidades where placas = 'PRB0001';

select throws_ok(
  $$ insert into public.conductor_estado (conductor_id, estado, unidad_id)
     select '00000000-0000-0000-0000-0000000000c2', 'disponible', id
     from public.unidades where placas = 'PRB0001' $$,
  '23505', null,
  'Una unidad no puede estar en servicio con dos conductores'
);

select throws_ok(
  $$ insert into public.conductor_estado (conductor_id, estado)
     values ('00000000-0000-0000-0000-0000000000c2', 'disponible') $$,
  '23514', null,
  'No se puede estar disponible sin elegir unidad'
);

select throws_ok(
  $$ insert into public.perfiles (id, rol, nombre)
     values ('00000000-0000-0000-0000-0000000000a1', 'pasajero', 'Pasajero Sin Tel') $$,
  '23514', null,
  'Un pasajero debe tener teléfono'
);

select * from finish();
rollback;
