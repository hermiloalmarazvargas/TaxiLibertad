-- Pruebas de autenticación: teléfonos, hook del token y registro de pasajero.
begin;
create extension if not exists pgtap with schema extensions;

select plan(22);

-- ── Datos de prueba ──────────────────────────────────────────────────
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'sinperfil@prueba.local'),
  ('00000000-0000-0000-0000-000000000002', 'conductor@prueba.local'),
  ('00000000-0000-0000-0000-000000000003', 'despacho@prueba.local'),
  ('00000000-0000-0000-0000-000000000004', 'inactivo@prueba.local'),
  ('00000000-0000-0000-0000-000000000005', 'bloqueado@prueba.local'),
  ('00000000-0000-0000-0000-000000000006', 'nuevo@prueba.local'),
  ('00000000-0000-0000-0000-000000000007', 'otro@prueba.local');

insert into public.sitios (nombre) values ('Sitio Auth');

insert into public.perfiles (id, rol, nombre, usuario, telefono, sitio_id, activo)
select v.id::uuid, v.rol::public.rol_usuario, v.nombre, v.usuario, v.telefono,
       case when v.con_sitio then s.id end, v.activo
from public.sitios s
cross join (values
  ('00000000-0000-0000-0000-000000000002', 'conductor',   'Conductor',   'prueba.cond', null,            false, true),
  ('00000000-0000-0000-0000-000000000003', 'despachador', 'Despachador', 'prueba.desp', null,            true,  true),
  ('00000000-0000-0000-0000-000000000004', 'conductor',   'Inactivo',    'prueba.inac', null,            false, false),
  ('00000000-0000-0000-0000-000000000005', 'pasajero',    'Bloqueado',   null,          '+529510000099', false, true)
) as v (id, rol, nombre, usuario, telefono, con_sitio, activo)
where s.nombre = 'Sitio Auth';

insert into public.telefonos_bloqueados (telefono, motivo)
values ('+529510000099', 'Pedidos falsos'), ('+529510000098', 'Pedidos falsos');

create function pg_temp.evento(p_user text) returns jsonb language sql as $$
  select jsonb_build_object(
    'user_id', p_user,
    'authentication_method', 'password',
    'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'rol', 'admin'));
$$;

-- ── Teléfonos ────────────────────────────────────────────────────────
select is(public.normalizar_telefono('951 123 4567')::text, '+529511234567', 'Teléfono con espacios');
select is(public.normalizar_telefono('+52 (951) 123-4567')::text, '+529511234567', 'Teléfono con +52 y signos');
select is(public.normalizar_telefono('529511234567')::text, '+529511234567', 'Teléfono con 52 sin +');
select throws_ok($$ select public.normalizar_telefono('12345') $$, '22023', null, 'Teléfono incompleto es rechazado');

-- ── Reglas de perfiles ───────────────────────────────────────────────
select throws_ok(
  $$ insert into public.perfiles (id, rol, nombre, telefono, usuario)
     values ('00000000-0000-0000-0000-000000000007', 'pasajero', 'Pasajero', '+529510000001', 'pasajero.x') $$,
  '23514', null, 'Un pasajero no tiene usuario');

select throws_ok(
  $$ insert into public.perfiles (id, rol, nombre)
     values ('00000000-0000-0000-0000-000000000007', 'conductor', 'Sin Usuario') $$,
  '23514', null, 'El personal debe tener usuario');

-- ── Hook del token ───────────────────────────────────────────────────
select is(
  public.custom_access_token_hook(pg_temp.evento('00000000-0000-0000-0000-000000000001')) -> 'claims' ->> 'rol',
  null,
  'Sin perfil: el token no lleva rol (y se descarta un rol inyectado)');

select is(
  public.custom_access_token_hook(pg_temp.evento('00000000-0000-0000-0000-000000000002')) -> 'claims' ->> 'rol',
  'conductor',
  'Conductor: el token lleva rol conductor (no el "admin" inyectado)');

select is(
  (public.custom_access_token_hook(pg_temp.evento('00000000-0000-0000-0000-000000000003')) -> 'claims' ->> 'sitio_id')::bigint,
  (select id from public.sitios where nombre = 'Sitio Auth'),
  'Despachador de sitio: el token lleva sitio_id');

select is(
  public.custom_access_token_hook(pg_temp.evento('00000000-0000-0000-0000-000000000004')) -> 'error' ->> 'http_code',
  '403',
  'Cuenta desactivada: no recibe token');

select is(
  public.custom_access_token_hook(pg_temp.evento('00000000-0000-0000-0000-000000000005')) -> 'error' ->> 'http_code',
  '403',
  'Pasajero con número bloqueado: no recibe token');

-- ── Hook de creación de usuarios ─────────────────────────────────────
select is(
  public.before_user_created_hook('{"user": {"is_anonymous": true, "app_metadata": {}}}'),
  '{}'::jsonb,
  'Se permite crear usuarios anónimos');

select is(
  public.before_user_created_hook('{"user": {"is_anonymous": false, "app_metadata": {"alta": "admin"}}}'),
  '{}'::jsonb,
  'Se permiten cuentas creadas por el admin');

select is(
  public.before_user_created_hook('{"user": {"is_anonymous": false, "app_metadata": {"provider": "email"}}}') -> 'error' ->> 'http_code',
  '403',
  'Se rechaza el registro por cuenta propia con correo');

-- ── Permisos ─────────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000006","role":"authenticated"}', true);

select throws_ok(
  $$ select public.custom_access_token_hook('{}'::jsonb) $$,
  '42501', null, 'Un usuario normal no puede ejecutar el hook');

-- ── Registro de pasajero (como usuario anónimo 006) ──────────────────
select is(
  (public.registrar_pasajero('  María López ', '951 222 3344')).telefono::text,
  '+529512223344',
  'Registro crea el perfil con el teléfono normalizado');

select is(
  (public.registrar_pasajero('María L.', '951 222 3344')).nombre,
  'María L.',
  'Registrarse de nuevo actualiza el nombre');

select throws_ok(
  $$ select public.registrar_pasajero('Falso', '9510000098') $$,
  '42501', null, 'No se puede registrar con un número bloqueado');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);

select throws_ok(
  $$ select public.registrar_pasajero('Conductor', '9513334455') $$,
  '42501', null, 'El personal no puede convertirse en pasajero');

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);

select throws_ok(
  $$ select public.registrar_pasajero('Nadie', '9513334455') $$,
  '42501', null, 'Sin sesión no se puede registrar');

set local role anon;

select throws_ok(
  $$ select public.registrar_pasajero('Anon', '9513334455') $$,
  '42501', null, 'El rol anon no puede ejecutar registrar_pasajero');

reset role;

select is(
  (select rol::text from public.perfiles where id = '00000000-0000-0000-0000-000000000006'),
  'pasajero',
  'El perfil registrado quedó como pasajero');

select * from finish();
rollback;
