-- =====================================================================
-- Fase 1 · Paso 3: permisos y políticas RLS
--
-- Dos capas:
--   1. GRANT: qué operaciones (y columnas) puede intentar cada rol de
--      Postgres. Supabase da TODO a anon y authenticated por defecto;
--      aquí se quita todo y se otorga solo lo necesario.
--   2. RLS: qué FILAS ve o modifica cada usuario según su rol de la app
--      (claim "rol" del JWT, ver custom_access_token_hook).
--
-- Los cambios de estado de viajes, ofertas y conductores NO se hacen con
-- UPDATE directo: irán por funciones RPC (paso 4).
--
-- Nota: los pasajeros anónimos usan el rol de Postgres "authenticated";
-- "anon" es solo quien no ha iniciado sesión y no necesita nada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Quitar los permisos por defecto
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon;

-- Que las tablas y funciones nuevas tampoco nazcan abiertas.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;

-- ---------------------------------------------------------------------
-- 2. Funciones auxiliares (leen el JWT; no consultan tablas)
-- ---------------------------------------------------------------------
create or replace function public.sitio_actual()
returns bigint
language sql
stable
set search_path = ''
as $$
  select nullif(auth.jwt() ->> 'sitio_id', '')::bigint;
$$;

create or replace function public.es_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(public.rol_actual() = 'admin', false);
$$;

create or replace function public.es_staff()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(public.rol_actual() in ('despachador', 'admin'), false);
$$;

-- Admin y despacho central ven todos los sitios; un despachador de sitio
-- ve el suyo y lo que aún no tiene sitio (viajes buscando conductor).
create or replace function public.puede_ver_sitio(p_sitio_id bigint)
returns boolean
language sql
stable
set search_path = ''
as $$
  select public.es_admin()
      or (public.rol_actual() = 'despachador'
          and (public.sitio_actual() is null
               or p_sitio_id is null
               or p_sitio_id = public.sitio_actual()));
$$;

-- Con revoke ... from public, estas funciones las necesita authenticated
-- (se evalúan dentro de las políticas).
grant execute on function
  public.rol_actual(), public.sitio_actual(), public.es_admin(),
  public.es_staff(), public.puede_ver_sitio(bigint),
  public.punto(double precision, double precision),
  public.zona_de(extensions.geography),
  public.tarifa_estimada(double precision, double precision, double precision, double precision),
  public.normalizar_telefono(text)
to authenticated;

-- ---------------------------------------------------------------------
-- 3. Permisos por tabla (capa GRANT)
-- ---------------------------------------------------------------------
-- Catálogos: lectura para todos; escritura la limita RLS al admin.
grant select, insert, update, delete on public.sitios, public.unidades,
  public.zonas, public.tarifas, public.conductores to authenticated;

-- Perfiles: se crean con registrar_pasajero o por el admin (llave secreta).
grant select on public.perfiles to authenticated;
grant update (nombre, telefono, activo, sitio_id) on public.perfiles to authenticated;

grant select, insert, delete on public.telefonos_bloqueados to authenticated;

-- El conductor solo puede escribir directamente su ubicación; cambiar de
-- estado o de unidad será por RPC.
grant select on public.conductor_estado to authenticated;
grant update (ubicacion, rumbo, precision_m, ubicacion_en) on public.conductor_estado to authenticated;

grant select, insert, delete on public.dispositivos to authenticated;

-- Viajes: solo lectura. Crear, aceptar, cancelar, etc. será por RPC.
grant select on public.viajes, public.ofertas_viaje, public.viaje_eventos to authenticated;

-- Quien bloquea un número queda registrado automáticamente.
alter table public.telefonos_bloqueados alter column bloqueado_por set default auth.uid();
alter table public.tarifas alter column actualizado_por set default auth.uid();

-- ---------------------------------------------------------------------
-- 4. Políticas RLS (capa de filas)
-- Las funciones van envueltas en (select ...) para que Postgres las
-- evalúe una vez por consulta y no una vez por fila.
-- ---------------------------------------------------------------------

-- ── Catálogos: sitios, zonas, tarifas ───────────────────────────────
create policy "usuarios con rol leen sitios"
  on public.sitios for select to authenticated
  using ((select public.rol_actual()) is not null);

create policy "admin administra sitios"
  on public.sitios for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

create policy "usuarios con rol leen zonas"
  on public.zonas for select to authenticated
  using ((select public.rol_actual()) is not null);

create policy "admin administra zonas"
  on public.zonas for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

create policy "usuarios con rol leen tarifas"
  on public.tarifas for select to authenticated
  using ((select public.rol_actual()) is not null);

create policy "admin administra tarifas"
  on public.tarifas for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ── Unidades ────────────────────────────────────────────────────────
create policy "staff lee unidades de sus sitios"
  on public.unidades for select to authenticated
  using ((select public.puede_ver_sitio(sitio_id)));

create policy "conductor lee unidades activas de su sitio"
  on public.unidades for select to authenticated
  using (
    (select public.rol_actual()) = 'conductor'
    and activo
    and sitio_id = (select public.sitio_actual())
  );

-- Para identificar el taxi que viene (número económico, placas, color).
create policy "pasajero lee la unidad de su viaje activo"
  on public.unidades for select to authenticated
  using (exists (
    select 1 from public.viajes v
    where v.unidad_id = unidades.id
      and v.pasajero_id = (select auth.uid())
      and v.estado in ('asignado', 'conductor_llego', 'en_curso')
  ));

create policy "admin administra unidades"
  on public.unidades for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ── Perfiles ────────────────────────────────────────────────────────
-- El nombre del conductor para el pasajero (y viceversa) se dará por RPC
-- solo durante el viaje, sin exponer la tabla.
create policy "cada quien lee su perfil"
  on public.perfiles for select to authenticated
  using (id = (select auth.uid()));

create policy "staff lee perfiles"
  on public.perfiles for select to authenticated
  using ((select public.es_staff()));

create policy "admin actualiza perfiles"
  on public.perfiles for update to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ── Teléfonos bloqueados ────────────────────────────────────────────
create policy "staff lee bloqueos"
  on public.telefonos_bloqueados for select to authenticated
  using ((select public.es_staff()));

create policy "staff bloquea numeros"
  on public.telefonos_bloqueados for insert to authenticated
  with check ((select public.es_staff()) and bloqueado_por = (select auth.uid()));

create policy "staff desbloquea numeros"
  on public.telefonos_bloqueados for delete to authenticated
  using ((select public.es_staff()));

-- ── Conductores ─────────────────────────────────────────────────────
create policy "conductor lee su registro"
  on public.conductores for select to authenticated
  using (perfil_id = (select auth.uid()));

create policy "staff lee conductores de sus sitios"
  on public.conductores for select to authenticated
  using ((select public.puede_ver_sitio(sitio_id)));

create policy "admin administra conductores"
  on public.conductores for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ── Estado del conductor ────────────────────────────────────────────
create policy "conductor lee su estado"
  on public.conductor_estado for select to authenticated
  using (conductor_id = (select auth.uid()));

create policy "staff lee estado de conductores de sus sitios"
  on public.conductor_estado for select to authenticated
  using (exists (
    select 1 from public.conductores c
    where c.perfil_id = conductor_estado.conductor_id
      and (select public.puede_ver_sitio(c.sitio_id))
  ));

-- Para ver al taxi acercarse en el mapa (también vía Realtime).
create policy "pasajero ve al conductor de su viaje activo"
  on public.conductor_estado for select to authenticated
  using (exists (
    select 1 from public.viajes v
    where v.conductor_id = conductor_estado.conductor_id
      and v.pasajero_id = (select auth.uid())
      and v.estado in ('asignado', 'conductor_llego', 'en_curso')
  ));

-- Solo puede reportar ubicación estando en servicio: fuera de servicio
-- no se rastrea a nadie.
create policy "conductor reporta su ubicacion en servicio"
  on public.conductor_estado for update to authenticated
  using (conductor_id = (select auth.uid()) and estado <> 'fuera_de_servicio')
  with check (conductor_id = (select auth.uid()) and estado <> 'fuera_de_servicio');

-- ── Dispositivos (tokens FCM) ───────────────────────────────────────
create policy "cada quien administra sus dispositivos"
  on public.dispositivos for all to authenticated
  using (perfil_id = (select auth.uid()))
  with check (perfil_id = (select auth.uid()));

-- ── Viajes ──────────────────────────────────────────────────────────
create policy "pasajero lee sus viajes"
  on public.viajes for select to authenticated
  using (pasajero_id = (select auth.uid()));

-- Los datos de una OFERTA (antes de aceptar) se darán por RPC con
-- columnas limitadas; aquí el conductor solo ve los viajes que son suyos.
create policy "conductor lee sus viajes"
  on public.viajes for select to authenticated
  using (conductor_id = (select auth.uid()));

create policy "staff lee viajes de sus sitios"
  on public.viajes for select to authenticated
  using ((select public.puede_ver_sitio(sitio_id)));

create policy "conductor lee sus ofertas"
  on public.ofertas_viaje for select to authenticated
  using (conductor_id = (select auth.uid()));

create policy "staff lee ofertas"
  on public.ofertas_viaje for select to authenticated
  using ((select public.es_staff()));

-- Quien puede ver el viaje puede ver su bitácora (hereda la RLS de viajes).
create policy "eventos visibles si el viaje es visible"
  on public.viaje_eventos for select to authenticated
  using (exists (select 1 from public.viajes v where v.id = viaje_eventos.viaje_id));
