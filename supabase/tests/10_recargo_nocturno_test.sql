-- Pruebas: recargo nocturno (porcentaje, horario que cruza la medianoche).
begin;
create extension if not exists pgtap with schema extensions;

select plan(15);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000010' || s)::uuid, s || '@recargo.local'
from unnest(array['a0', 'd0', 'e1']) as s;

create function pg_temp.uid(p text) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-0000000010' || p)::uuid $$;

insert into public.perfiles (id, rol, nombre, usuario, telefono) values
  (pg_temp.uid('a0'), 'admin', 'Admin', 'rec.a0', null),
  (pg_temp.uid('d0'), 'despachador', 'Despacho', 'rec.d0', null),
  (pg_temp.uid('e1'), 'pasajero', 'Pasajero', null, '+529514440001');

-- Zonas propias lejos de Miahuatlán: A→B cuesta 45, A→C cuesta 42.50, A→D sin tarifa.
insert into public.zonas (nombre, poligono)
select 'Rec ' || n, extensions.st_multi(extensions.st_makeenvelope(x, 0, x + 1, 1, 4326))
from (values ('A', 0), ('B', 1), ('C', 2), ('D', 3)) as z (n, x);

insert into public.tarifas (zona_origen_id, zona_destino_id, monto)
select a.id, b.id, t.monto
from (values ('Rec B', 45), ('Rec C', 42.50)) as t (destino, monto)
join public.zonas a on a.nombre = 'Rec A'
join public.zonas b on b.nombre = t.destino;

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

-- Tarifa A→(destino) a una hora local de Oaxaca.
create function pg_temp.tarifa(p_destino_lng float, p_hora text)
returns table (monto numeric, monto_base numeric, recargo numeric, nocturno boolean)
language sql as $$
  select t.monto, t.monto_base, t.recargo, t.nocturno
  from public.tarifa_estimada(0.5, 0.5, 0.5, p_destino_lng, ('2026-03-10 ' || p_hora || '-06')::timestamptz) t
$$;

-- Configuración inicial: 10 %, de 22:00 a 06:00.
select is((select (recargo_nocturno_pct, recargo_desde, recargo_hasta)::text from public.configuracion),
  '(10.00,22:00:00,06:00:00)', 'Por omisión: 10 % de 22:00 a 06:00');

select pg_temp.como('e1');

select is((select (monto, recargo, nocturno)::text from pg_temp.tarifa(1.5, '12:00')),
  '(45.00,0,f)', 'De día no hay recargo');
select is((select (monto, monto_base, recargo, nocturno)::text from pg_temp.tarifa(1.5, '23:00')),
  '(50.00,45.00,5,t)', 'De noche: 45 + 10 % = 4.50 → se redondea a $5 → $50');
select is((select nocturno from pg_temp.tarifa(1.5, '21:59')), false, 'A las 21:59 todavía no aplica');
select is((select nocturno from pg_temp.tarifa(1.5, '22:00')), true, 'A las 22:00 ya aplica');
select is((select nocturno from pg_temp.tarifa(1.5, '05:59')), true, 'A las 05:59 (madrugada) aplica');
select is((select nocturno from pg_temp.tarifa(1.5, '06:00')), false, 'A las 06:00 ya no aplica');
select is((select (monto, recargo)::text from pg_temp.tarifa(2.5, '23:00')),
  '(46.50,4)', 'Tarifa con centavos: 42.50 + 4.25 → recargo redondeado a $4');
select is((select (monto, recargo, nocturno)::text from pg_temp.tarifa(3.5, '23:00')),
  '(,,t)', 'A convenir sigue a convenir de noche (pero se indica que es horario nocturno)');

-- ── Solo el admin cambia la configuración ───────────────────────────
select pg_temp.como('d0');
update public.configuracion set recargo_nocturno_pct = 50;
reset role;
select is((select recargo_nocturno_pct from public.configuracion), 10.00, 'El despacho no puede cambiar el recargo');

select pg_temp.como('a0');
update public.configuracion set recargo_nocturno_pct = 20, recargo_desde = '01:00', recargo_hasta = '05:00';
select is((select (monto, recargo)::text from pg_temp.tarifa(1.5, '03:00')),
  '(54.00,9)', 'Horario sin cruzar la medianoche (01–05) y 20 %: 45 + 9 = $54');
select is((select nocturno from pg_temp.tarifa(1.5, '23:00')), false, 'Fuera del nuevo horario no aplica');
select is((select actualizado_por from public.configuracion), pg_temp.uid('a0'), 'Se registra quién cambió el recargo');

update public.configuracion set recargo_nocturno_pct = 0, recargo_desde = '00:00', recargo_hasta = '23:59:59';
select is((select (monto, nocturno)::text from pg_temp.tarifa(1.5, '03:00')),
  '(45.00,f)', 'Con 0 % el recargo queda desactivado');

-- ── El viaje guarda el recargo cobrado ──────────────────────────────
update public.configuracion set recargo_nocturno_pct = 10, recargo_desde = '00:00', recargo_hasta = '23:59:59';
select pg_temp.como('e1');
select public.solicitar_viaje('00000000-0000-0000-0000-000000001001', 0.5, 0.5, null, 0.5, 1.5);
reset role;
select is(
  (select (tarifa_monto, tarifa_recargo)::text from public.viajes
   where client_request_id = '00000000-0000-0000-0000-000000001001'),
  '(50.00,5.00)', 'El viaje guarda el total y, aparte, el recargo incluido');

select * from finish();
rollback;
