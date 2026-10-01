-- Pruebas: administración de unidades y sitios desde el panel.
begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000007' || s)::uuid, s || '@catalogos.local'
from unnest(array['a0', 'd0', 'c1']) as s;

create function pg_temp.uid(p text) returns uuid language sql immutable
as $$ select ('00000000-0000-0000-0000-0000000007' || p)::uuid $$;

insert into public.sitios (nombre) values ('Cat Sitio A'), ('Cat Sitio B');

insert into public.perfiles (id, rol, nombre, usuario) values
  (pg_temp.uid('a0'), 'admin',       'Admin',    'cat.a0'),
  (pg_temp.uid('d0'), 'despachador', 'Despacho', 'cat.d0'),
  (pg_temp.uid('c1'), 'conductor',   'Chofer',   'cat.c1');

insert into public.conductores (perfil_id, sitio_id)
select pg_temp.uid('c1'), id from public.sitios where nombre = 'Cat Sitio A';

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

-- ── Admin: alta y edición ────────────────────────────────────────────
select pg_temp.como('a0');
select lives_ok(
  $$ insert into public.unidades (sitio_id, numero_economico, placas, marca, color)
     select id, '10', 'CAT0010', 'Nissan', 'Blanco' from public.sitios where nombre = 'Cat Sitio A' $$,
  'El admin da de alta una unidad');
select lives_ok(
  $$ insert into public.unidades (sitio_id, numero_economico, placas)
     select id, '11', 'CAT0011' from public.sitios where nombre = 'Cat Sitio A' $$,
  'El admin da de alta otra unidad');
select is(pg_temp.error_de(
  $$ insert into public.unidades (sitio_id, numero_economico, placas)
     select id, '10', 'CAT0099' from public.sitios where nombre = 'Cat Sitio A' $$),
  '23505', 'No se repite el número económico dentro del mismo sitio');
select lives_ok(
  $$ insert into public.sitios (nombre, telefono) values ('Cat Sitio C', '+529510001111') $$,
  'El admin da de alta un sitio');

-- ── Despacho: solo lectura ───────────────────────────────────────────
select pg_temp.como('d0');
select is(pg_temp.error_de(
  $$ insert into public.unidades (sitio_id, numero_economico, placas)
     select id, '12', 'CAT0012' from public.sitios where nombre = 'Cat Sitio A' $$),
  '42501', 'El despacho no puede dar de alta unidades');

-- ── Unidad en servicio ───────────────────────────────────────────────
select pg_temp.como('c1');
select public.cambiar_disponibilidad('disponible', (select id from public.unidades where placas = 'CAT0010'));

select pg_temp.como('a0');
select is(pg_temp.error_de($$ update public.unidades set activo = false where placas = 'CAT0010' $$),
  'unidad_en_servicio', 'No se desactiva una unidad que está en servicio');
select is(pg_temp.error_de(
  $$ update public.unidades set sitio_id = (select id from public.sitios where nombre = 'Cat Sitio B')
     where placas = 'CAT0010' $$),
  'unidad_en_servicio', 'No se mueve de sitio una unidad que está en servicio');
select lives_ok($$ update public.unidades set color = 'Blanco/Rojo' where placas = 'CAT0010' $$,
  'Sí se pueden editar otros datos de una unidad en servicio');

-- ── Sitio con activos ────────────────────────────────────────────────
select is(pg_temp.error_de($$ update public.sitios set activo = false where nombre = 'Cat Sitio A' $$),
  'sitio_con_activos', 'No se desactiva un sitio con unidades o conductores activos');

select * from finish();
rollback;
