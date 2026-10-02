-- Pruebas: guardar zonas dibujadas en el panel y registro de cambios de tarifas.
begin;
create extension if not exists pgtap with schema extensions;

select plan(11);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000009' || s)::uuid, s || '@zonas.local'
from unnest(array['a0', 'd0']) as s;

create function pg_temp.uid(p text) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-0000000009' || p)::uuid $$;

insert into public.perfiles (id, rol, nombre, usuario) values
  (pg_temp.uid('a0'), 'admin', 'Admin', 'zon.a0'),
  (pg_temp.uid('d0'), 'despachador', 'Despacho', 'zon.d0');

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

-- Cuadro de prueba lejos de Miahuatlán (lat/lng 1..2), como lo manda Leaflet.
create function pg_temp.cuadro(x0 float, y0 float, x1 float, y1 float) returns jsonb language sql immutable as $$
  select jsonb_build_object('type', 'Polygon', 'coordinates',
    jsonb_build_array(jsonb_build_array(
      jsonb_build_array(x0, y0), jsonb_build_array(x1, y0), jsonb_build_array(x1, y1),
      jsonb_build_array(x0, y1), jsonb_build_array(x0, y0))))
$$;

select pg_temp.como('a0');

select is(
  (public.guardar_zona('  Zona Dibujada ', '#ff0000', pg_temp.cuadro(1, 1, 1.01, 1.01))).nombre,
  'Zona Dibujada', 'El admin guarda una zona dibujada (nombre sin espacios sobrantes)');
select is(
  (select extensions.geometrytype(poligono) from public.zonas where nombre = 'Zona Dibujada'),
  'MULTIPOLYGON', 'El polígono se guarda como MultiPolygon');
select is(
  (select zona_origen from public.tarifa_estimada(1.005, 1.005)),
  'Zona Dibujada', 'La zona nueva ya se usa para calcular tarifas');

select is(pg_temp.error_de(format($$ select public.guardar_zona('Moño', '#00ff00', %L) $$,
    '{"type":"Polygon","coordinates":[[[1,1],[1.01,1.01],[1.01,1],[1,1.01],[1,1]]]}')),
  'poligono_invalido', 'Un polígono que se cruza consigo mismo es rechazado');
select is(pg_temp.error_de(format($$ select public.guardar_zona('Gigante', '#00ff00', %L) $$,
    pg_temp.cuadro(1, 1, 2, 2))),
  'poligono_invalido', 'Una zona de más de 500 km² es rechazada');
select is(pg_temp.error_de(format($$ select public.guardar_zona('Zona Dibujada', '#00ff00', %L) $$,
    pg_temp.cuadro(1.1, 1.1, 1.11, 1.11))),
  'nombre_repetido', 'No se repite el nombre de una zona');
select is(pg_temp.error_de($$ select public.guardar_zona('Punto', '#00ff00', '{"type":"Point","coordinates":[1,1]}') $$),
  'poligono_invalido', 'Un punto no es una zona');

-- Editar la forma: ahora el punto 1.005 queda fuera y el 1.025 dentro.
select public.guardar_zona('Zona Dibujada', '#ff0000', pg_temp.cuadro(1.02, 1.02, 1.03, 1.03),
  (select id from public.zonas where nombre = 'Zona Dibujada'));
select ok(
  (select zona_origen_id is null from public.tarifa_estimada(1.005, 1.005))
  and (select zona_origen = 'Zona Dibujada' from public.tarifa_estimada(1.025, 1.025)),
  'Editar la forma cambia qué puntos caen en la zona');

-- ── Tarifas: quién y cuándo ──────────────────────────────────────────
insert into public.tarifas (zona_origen_id, zona_destino_id, monto, actualizado_por)
select id, id, 30, '00000000-0000-0000-0000-000000000000' from public.zonas where nombre = 'Zona Dibujada';
select is(
  (select actualizado_por from public.tarifas t join public.zonas z on z.id = t.zona_origen_id
   where z.nombre = 'Zona Dibujada'),
  pg_temp.uid('a0'), 'La tarifa registra al admin que la capturó (no se puede falsificar)');

-- ── Permisos ─────────────────────────────────────────────────────────
select pg_temp.como('d0');
select is(pg_temp.error_de(format($$ select public.guardar_zona('Otra', '#00ff00', %L) $$,
    pg_temp.cuadro(1.2, 1.2, 1.21, 1.21))),
  '42501', 'El despacho no puede dibujar zonas');
select is(pg_temp.error_de($$ update public.tarifas set monto = 1 $$),
  null, 'El despacho no puede cambiar tarifas (RLS no le deja filas, sin error)');

select * from finish();
rollback;
