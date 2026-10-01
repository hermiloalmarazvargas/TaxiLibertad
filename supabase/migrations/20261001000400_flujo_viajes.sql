-- =====================================================================
-- Fase 1 · Paso 4: flujo de viajes (RPC), asignación automática y Realtime
--
-- Reglas generales:
--   · Las apps nunca hacen UPDATE a viajes/ofertas: todo pasa por estas RPC.
--   · Toda RPC es idempotente ante reintentos (señal intermitente): repetir
--     la misma acción devuelve el estado actual en lugar de fallar.
--   · Errores de negocio: errcode P0001, mensaje en español para mostrar al
--     usuario y un código estable en "hint" para que la app decida qué hacer.
--   · Orden de bloqueo de filas: viaje → oferta → conductor_estado.
--     Seguir siempre este orden evita bloqueos mutuos (deadlocks).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Esquema privado: funciones internas que la API no expone
-- ---------------------------------------------------------------------
create schema privado;
revoke all on schema privado from public, anon, authenticated;

-- Parámetros del despacho automático (cambiar aquí con una migración).
create function privado.segundos_oferta() returns integer
language sql immutable as $$ select 20 $$;

create function privado.minutos_busqueda() returns integer
language sql immutable as $$ select 5 $$;

create function privado.radio_busqueda_m() returns integer
language sql immutable as $$ select 15000 $$;

create function privado.segundos_ubicacion_vigente() returns integer
language sql immutable as $$ select 60 $$;

create function privado.error(p_codigo text, p_mensaje text) returns void
language plpgsql as $$
begin
  raise exception '%', p_mensaje using errcode = 'P0001', hint = p_codigo;
end;
$$;

create function privado.exigir_rol(variadic p_roles public.rol_usuario[]) returns void
language plpgsql stable set search_path = '' as $$
begin
  if public.rol_actual() is null or not (public.rol_actual() = any (p_roles)) then
    raise exception 'No tienes permiso para esta acción' using errcode = '42501';
  end if;
end;
$$;

create function privado.telefono_bloqueado(p_telefono text) returns boolean
language sql stable set search_path = '' as $$
  select exists (select 1 from public.telefonos_bloqueados where telefono = p_telefono);
$$;

-- ---------------------------------------------------------------------
-- Coordenadas legibles (las apps leen lat/lng, no el formato de PostGIS)
-- ---------------------------------------------------------------------
alter table public.viajes
  add column origen_lat  double precision generated always as (extensions.st_y(origen::extensions.geometry)) stored,
  add column origen_lng  double precision generated always as (extensions.st_x(origen::extensions.geometry)) stored,
  add column destino_lat double precision generated always as (extensions.st_y(destino::extensions.geometry)) stored,
  add column destino_lng double precision generated always as (extensions.st_x(destino::extensions.geometry)) stored;

alter table public.conductor_estado
  add column lat double precision generated always as (extensions.st_y(ubicacion::extensions.geometry)) stored,
  add column lng double precision generated always as (extensions.st_x(ubicacion::extensions.geometry)) stored;

-- ---------------------------------------------------------------------
-- Marcas de tiempo del conductor (las pone el servidor, no el teléfono)
-- ---------------------------------------------------------------------
-- La hora del teléfono puede estar mal; para saber si la ubicación está
-- "fresca" se usa la hora en que llegó al servidor.
revoke update (ubicacion_en) on public.conductor_estado from authenticated;

create function privado.conductor_estado_actualizado() returns trigger
language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

create function privado.conductor_estado_ubicacion() returns trigger
language plpgsql as $$
begin
  new.ubicacion_en := case when new.ubicacion is null then null else now() end;
  return new;
end;
$$;

create trigger conductor_estado_actualizado
  before update on public.conductor_estado
  for each row execute function privado.conductor_estado_actualizado();

create trigger conductor_estado_ubicacion
  before insert or update of ubicacion on public.conductor_estado
  for each row execute function privado.conductor_estado_ubicacion();

-- ---------------------------------------------------------------------
-- Bitácora automática de cambios de estado
-- ---------------------------------------------------------------------
create function privado.registrar_evento_viaje() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.estado is distinct from old.estado then
    insert into public.viaje_eventos (viaje_id, estado_anterior, estado_nuevo, actor_id, ocurrido_en)
    values (
      new.id,
      case when tg_op = 'UPDATE' then old.estado end,
      new.estado,
      auth.uid(),
      case new.estado
        when 'asignado'        then coalesce(new.asignado_en, now())
        when 'conductor_llego' then coalesce(new.llego_en, now())
        when 'en_curso'        then coalesce(new.iniciado_en, now())
        when 'completado'      then coalesce(new.terminado_en, now())
        when 'cancelado'       then coalesce(new.cancelado_en, now())
        else now()
      end
    );
  end if;
  return null;
end;
$$;

create trigger viajes_registrar_evento
  after insert or update of estado on public.viajes
  for each row execute function privado.registrar_evento_viaje();

-- ---------------------------------------------------------------------
-- Núcleo: crear, ofrecer y asignar
-- ---------------------------------------------------------------------
create function privado.validar_coordenadas(p_lat double precision, p_lng double precision) returns void
language plpgsql immutable as $$
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform privado.error('coordenadas_invalidas', 'La ubicación no es válida');
  end if;
end;
$$;

create function privado.insertar_viaje(
  p_canal              public.canal_viaje,
  p_client_request_id  uuid,
  p_pasajero_id        uuid,
  p_contacto_nombre    text,
  p_contacto_telefono  text,
  p_origen_lat         double precision,
  p_origen_lng         double precision,
  p_origen_referencia  text,
  p_destino_lat        double precision,
  p_destino_lng        double precision,
  p_destino_referencia text
) returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_tarifa  record;
  v_viaje   public.viajes;
begin
  perform privado.validar_coordenadas(p_origen_lat, p_origen_lng);
  if (p_destino_lat is null) <> (p_destino_lng is null) then
    perform privado.error('coordenadas_invalidas', 'El destino no es válido');
  end if;
  if p_destino_lat is not null then
    perform privado.validar_coordenadas(p_destino_lat, p_destino_lng);
  end if;

  select * into v_tarifa
  from public.tarifa_estimada(p_origen_lat, p_origen_lng, p_destino_lat, p_destino_lng);

  insert into public.viajes (
    client_request_id, canal, pasajero_id, creado_por, contacto_nombre, contacto_telefono,
    origen, origen_referencia, destino, destino_referencia,
    zona_origen_id, zona_destino_id, tarifa_monto
  ) values (
    p_client_request_id, p_canal, p_pasajero_id, auth.uid(),
    nullif(trim(p_contacto_nombre), ''), p_contacto_telefono,
    public.punto(p_origen_lat, p_origen_lng), nullif(trim(p_origen_referencia), ''),
    case when p_destino_lat is not null then public.punto(p_destino_lat, p_destino_lng) end,
    nullif(trim(p_destino_referencia), ''),
    v_tarifa.zona_origen_id, v_tarifa.zona_destino_id, v_tarifa.monto
  )
  returning * into v_viaje;

  return v_viaje;
end;
$$;

-- Ofrece el viaje al conductor disponible más cercano que aún no lo haya
-- visto. Devuelve el conductor elegido o null si no hay nadie.
create function privado.ofrecer_siguiente(p_viaje_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_viaje      public.viajes;
  v_candidato  record;
  v_intentos   integer := 0;
begin
  select * into v_viaje from public.viajes where id = p_viaje_id for update;
  if not found or v_viaje.estado <> 'buscando' then
    return null;
  end if;
  if exists (select 1 from public.ofertas_viaje
             where viaje_id = p_viaje_id and respuesta = 'pendiente') then
    return null;
  end if;

  loop
    v_intentos := v_intentos + 1;

    select ce.conductor_id,
           extensions.st_distance(ce.ubicacion, v_viaje.origen)::integer as distancia_m
      into v_candidato
    from public.conductor_estado ce
    join public.conductores c on c.perfil_id = ce.conductor_id and c.activo
    join public.perfiles p on p.id = ce.conductor_id and p.activo
    where ce.estado = 'disponible'
      and ce.ubicacion_en > now() - make_interval(secs => privado.segundos_ubicacion_vigente())
      and extensions.st_dwithin(ce.ubicacion, v_viaje.origen, privado.radio_busqueda_m())
      and not exists (select 1 from public.ofertas_viaje o
                      where o.viaje_id = p_viaje_id and o.conductor_id = ce.conductor_id)
      and not exists (select 1 from public.ofertas_viaje o
                      where o.conductor_id = ce.conductor_id and o.respuesta = 'pendiente')
    -- No usar ORDER BY <-> (KNN de GiST): junto con FOR UPDATE falla con
    -- "attempted to lock invisible tuple". st_dwithin ya usa el índice y
    -- ordenar los pocos taxis que quedan por st_distance es barato.
    order by extensions.st_distance(ce.ubicacion, v_viaje.origen)
    limit 1
    for update of ce skip locked;

    if not found then
      if v_viaje.solicitado_en < now() - make_interval(mins => privado.minutos_busqueda()) then
        update public.viajes set estado = 'sin_conductor' where id = p_viaje_id;
      end if;
      return null;
    end if;

    begin
      insert into public.ofertas_viaje (viaje_id, conductor_id, distancia_m, expira_en)
      values (p_viaje_id, v_candidato.conductor_id, v_candidato.distancia_m,
              now() + make_interval(secs => privado.segundos_oferta()));
      return v_candidato.conductor_id;
    exception when unique_violation then
      -- Otro viaje le ofreció a este conductor al mismo tiempo: probar con el siguiente.
      if v_intentos >= 5 then
        return null;
      end if;
    end;
  end loop;
end;
$$;

-- Asigna un viaje (ya bloqueado por quien llama) a un conductor disponible.
create function privado.asignar(p_viaje_id uuid, p_conductor_id uuid) returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_estado  public.conductor_estado;
  v_sitio   bigint;
  v_viaje   public.viajes;
begin
  select ce.* into v_estado
  from public.conductor_estado ce
  join public.conductores c on c.perfil_id = ce.conductor_id and c.activo
  where ce.conductor_id = p_conductor_id
  for update of ce;

  if not found or v_estado.estado <> 'disponible' or v_estado.unidad_id is null then
    perform privado.error('conductor_no_disponible', 'El conductor no está disponible');
  end if;

  select sitio_id into v_sitio from public.conductores where perfil_id = p_conductor_id;

  update public.ofertas_viaje
  set respuesta = 'expirada', respondido_en = now()
  where viaje_id = p_viaje_id and respuesta = 'pendiente';

  update public.viajes
  set estado = 'asignado',
      conductor_id = p_conductor_id,
      unidad_id = v_estado.unidad_id,
      sitio_id = v_sitio,
      asignado_en = now()
  where id = p_viaje_id
  returning * into v_viaje;

  update public.conductor_estado set estado = 'ocupado' where conductor_id = p_conductor_id;

  return v_viaje;
end;
$$;

-- Lo ejecuta pg_cron cada 5 segundos: vence ofertas sin respuesta y
-- ofrece los viajes pendientes al siguiente conductor.
create function privado.procesar_ofertas_vencidas() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_viaje_id  uuid;
  v_ofrecidos integer := 0;
begin
  for v_viaje_id in
    select id from public.viajes
    where estado = 'buscando'
    order by solicitado_en
    for update skip locked
  loop
    update public.ofertas_viaje
    set respuesta = 'expirada', respondido_en = now()
    where viaje_id = v_viaje_id and respuesta = 'pendiente' and expira_en <= now();

    if privado.ofrecer_siguiente(v_viaje_id) is not null then
      v_ofrecidos := v_ofrecidos + 1;
    end if;
  end loop;

  return v_ofrecidos;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC del pasajero
-- ---------------------------------------------------------------------
create function public.solicitar_viaje(
  p_client_request_id   uuid,
  p_origen_lat          double precision,
  p_origen_lng          double precision,
  p_origen_referencia   text default null,
  p_destino_lat         double precision default null,
  p_destino_lng         double precision default null,
  p_destino_referencia  text default null
) returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := auth.uid();
  v_viaje  public.viajes;
begin
  perform privado.exigir_rol('pasajero');
  if p_client_request_id is null then
    perform privado.error('solicitud_invalida', 'Falta el identificador de la solicitud');
  end if;
  perform privado.validar_coordenadas(p_origen_lat, p_origen_lng);

  -- Reintento de una solicitud que ya llegó: devolver la misma.
  select * into v_viaje from public.viajes where client_request_id = p_client_request_id;
  if found then
    if v_viaje.pasajero_id is distinct from v_uid then
      perform privado.error('solicitud_invalida', 'Solicitud no válida');
    end if;
    return v_viaje;
  end if;

  -- Se revisa aquí (además del token) para que un bloqueo surta efecto de inmediato.
  if privado.telefono_bloqueado((select telefono from public.perfiles where id = v_uid)) then
    perform privado.error('telefono_bloqueado', 'Este número no puede pedir viajes. Comunícate con el sitio.');
  end if;

  if exists (select 1 from public.viajes
             where pasajero_id = v_uid
               and estado in ('buscando', 'asignado', 'conductor_llego', 'en_curso')) then
    perform privado.error('viaje_activo', 'Ya tienes un viaje en curso');
  end if;

  v_viaje := privado.insertar_viaje(
    'app', p_client_request_id, v_uid, null, null,
    p_origen_lat, p_origen_lng, p_origen_referencia,
    p_destino_lat, p_destino_lng, p_destino_referencia);

  perform privado.ofrecer_siguiente(v_viaje.id);
  return v_viaje;
end;
$$;

-- Viaje activo del pasajero con los datos del taxi asignado.
create function public.mi_viaje_activo()
returns table (
  viaje_id             uuid,
  estado               public.estado_viaje,
  origen_lat           double precision,
  origen_lng           double precision,
  origen_referencia    text,
  destino_lat          double precision,
  destino_lng          double precision,
  destino_referencia   text,
  zona_origen          text,
  zona_destino         text,
  tarifa_monto         numeric,
  solicitado_en        timestamptz,
  conductor_nombre     text,
  unidad_numero        text,
  unidad_placas        text,
  unidad_descripcion   text,
  conductor_lat        double precision,
  conductor_lng        double precision,
  conductor_ubicacion_en timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_rol('pasajero');

  return query
  select v.id, v.estado, v.origen_lat, v.origen_lng, v.origen_referencia,
         v.destino_lat, v.destino_lng, v.destino_referencia,
         zo.nombre, zd.nombre, v.tarifa_monto, v.solicitado_en,
         p.nombre, u.numero_economico, u.placas,
         nullif(concat_ws(' ', u.marca, u.color), ''),
         ce.lat, ce.lng, ce.ubicacion_en
  from public.viajes v
  left join public.zonas zo on zo.id = v.zona_origen_id
  left join public.zonas zd on zd.id = v.zona_destino_id
  left join public.perfiles p on p.id = v.conductor_id
  left join public.unidades u on u.id = v.unidad_id
  left join public.conductor_estado ce on ce.conductor_id = v.conductor_id
  where v.pasajero_id = auth.uid()
    and v.estado in ('buscando', 'asignado', 'conductor_llego', 'en_curso')
  order by v.solicitado_en desc
  limit 1;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC del conductor
-- ---------------------------------------------------------------------
create function public.cambiar_disponibilidad(
  p_estado     public.estado_conductor,
  p_unidad_id  bigint default null
) returns public.conductor_estado
language plpgsql security definer set search_path = '' as $$
declare
  v_uid      uuid := auth.uid();
  v_actual   public.conductor_estado;
  v_unidad   bigint;
  v_viaje_id uuid;
  v_result   public.conductor_estado;
begin
  perform privado.exigir_rol('conductor');

  -- Si hay una oferta pendiente, primero se bloquea su viaje (orden de bloqueo).
  select viaje_id into v_viaje_id
  from public.ofertas_viaje where conductor_id = v_uid and respuesta = 'pendiente';
  if v_viaje_id is not null then
    perform 1 from public.viajes where id = v_viaje_id for update;
  end if;

  insert into public.conductor_estado (conductor_id) values (v_uid) on conflict do nothing;
  select * into v_actual from public.conductor_estado where conductor_id = v_uid for update;

  if exists (select 1 from public.viajes
             where conductor_id = v_uid and estado in ('asignado', 'conductor_llego', 'en_curso')) then
    if p_estado = v_actual.estado then
      return v_actual;
    end if;
    perform privado.error('viaje_en_curso', 'Termina tu viaje antes de cambiar de estado');
  end if;

  if p_estado = 'fuera_de_servicio' then
    -- Fuera de servicio no se guarda la ubicación de nadie.
    update public.conductor_estado
    set estado = 'fuera_de_servicio', unidad_id = null,
        ubicacion = null, rumbo = null, precision_m = null
    where conductor_id = v_uid
    returning * into v_result;
  else
    v_unidad := coalesce(p_unidad_id, v_actual.unidad_id);
    if v_unidad is null then
      perform privado.error('unidad_requerida', 'Elige la unidad que vas a manejar');
    end if;
    if not exists (select 1 from public.unidades u
                   join public.conductores c on c.sitio_id = u.sitio_id
                   where u.id = v_unidad and u.activo and c.perfil_id = v_uid) then
      perform privado.error('unidad_invalida', 'Esa unidad no pertenece a tu sitio o está inactiva');
    end if;

    begin
      update public.conductor_estado
      set estado = p_estado, unidad_id = v_unidad
      where conductor_id = v_uid
      returning * into v_result;
    exception when unique_violation then
      perform privado.error('unidad_ocupada', 'Esa unidad ya está en servicio con otro conductor');
    end;
  end if;

  -- Si deja de estar disponible, suelta su oferta y el viaje pasa al siguiente.
  if p_estado <> 'disponible' and v_viaje_id is not null then
    update public.ofertas_viaje
    set respuesta = 'rechazada', respondido_en = now()
    where conductor_id = v_uid and respuesta = 'pendiente';
    perform privado.ofrecer_siguiente(v_viaje_id);
  end if;

  return v_result;
end;
$$;

-- Datos de la oferta pendiente, sin datos personales del pasajero.
-- segundos_restantes se calcula en el servidor: el reloj del teléfono no es confiable.
create function public.mi_oferta_pendiente()
returns table (
  oferta_id           bigint,
  viaje_id            uuid,
  segundos_restantes  integer,
  distancia_m         integer,
  origen_lat          double precision,
  origen_lng          double precision,
  origen_referencia   text,
  destino_lat         double precision,
  destino_lng         double precision,
  destino_referencia  text,
  zona_origen         text,
  zona_destino        text,
  tarifa_monto        numeric
)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_rol('conductor');

  return query
  select o.id, v.id,
         greatest(0, ceil(extract(epoch from o.expira_en - now())))::integer,
         o.distancia_m,
         v.origen_lat, v.origen_lng, v.origen_referencia,
         v.destino_lat, v.destino_lng, v.destino_referencia,
         zo.nombre, zd.nombre, v.tarifa_monto
  from public.ofertas_viaje o
  join public.viajes v on v.id = o.viaje_id
  left join public.zonas zo on zo.id = v.zona_origen_id
  left join public.zonas zd on zd.id = v.zona_destino_id
  where o.conductor_id = auth.uid()
    and o.respuesta = 'pendiente'
    and o.expira_en > now()
    and v.estado = 'buscando';
end;
$$;

create function public.responder_oferta(p_oferta_id bigint, p_aceptar boolean)
returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_oferta  public.ofertas_viaje;
  v_viaje   public.viajes;
begin
  perform privado.exigir_rol('conductor');

  select * into v_oferta from public.ofertas_viaje where id = p_oferta_id and conductor_id = v_uid;
  if not found then
    perform privado.error('oferta_no_encontrada', 'La oferta no existe');
  end if;

  select * into v_viaje from public.viajes where id = v_oferta.viaje_id for update;
  select * into v_oferta from public.ofertas_viaje where id = p_oferta_id for update;

  -- Reintentos de una respuesta que ya se registró.
  if v_oferta.respuesta = 'aceptada' and p_aceptar then
    return v_viaje;
  end if;
  if v_oferta.respuesta = 'rechazada' and not p_aceptar then
    return v_viaje;
  end if;

  if v_oferta.respuesta <> 'pendiente' or v_oferta.expira_en <= now() or v_viaje.estado <> 'buscando' then
    perform privado.error('oferta_vencida', 'La oferta ya no está disponible');
  end if;

  if not p_aceptar then
    update public.ofertas_viaje set respuesta = 'rechazada', respondido_en = now() where id = p_oferta_id;
    perform privado.ofrecer_siguiente(v_viaje.id);
    return v_viaje;
  end if;

  update public.ofertas_viaje set respuesta = 'aceptada', respondido_en = now() where id = p_oferta_id;
  return privado.asignar(v_viaje.id, v_uid);
end;
$$;

-- Viaje activo del conductor, con el contacto del pasajero.
create function public.mi_viaje_activo_conductor()
returns table (
  viaje_id            uuid,
  estado              public.estado_viaje,
  canal               public.canal_viaje,
  origen_lat          double precision,
  origen_lng          double precision,
  origen_referencia   text,
  destino_lat         double precision,
  destino_lng         double precision,
  destino_referencia  text,
  zona_origen         text,
  zona_destino        text,
  tarifa_monto        numeric,
  pasajero_nombre     text,
  pasajero_telefono   text,
  asignado_en         timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform privado.exigir_rol('conductor');

  return query
  select v.id, v.estado, v.canal, v.origen_lat, v.origen_lng, v.origen_referencia,
         v.destino_lat, v.destino_lng, v.destino_referencia,
         zo.nombre, zd.nombre, v.tarifa_monto,
         coalesce(v.contacto_nombre, p.nombre),
         coalesce(v.contacto_telefono, p.telefono)::text,
         v.asignado_en
  from public.viajes v
  left join public.zonas zo on zo.id = v.zona_origen_id
  left join public.zonas zd on zd.id = v.zona_destino_id
  left join public.perfiles p on p.id = v.pasajero_id
  where v.conductor_id = auth.uid()
    and v.estado in ('asignado', 'conductor_llego', 'en_curso');
end;
$$;

-- "Llegué", "Inicié viaje", "Terminé viaje".
-- p_ocurrido_en: hora del teléfono cuando se tocó el botón (puede llegar
-- tarde por falta de señal). Se acota entre la asignación y ahora.
create function public.avanzar_viaje(
  p_viaje_id     uuid,
  p_estado       public.estado_viaje,
  p_ocurrido_en  timestamptz default null
) returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := auth.uid();
  v_viaje  public.viajes;
  v_hora   timestamptz;
  v_orden  constant public.estado_viaje[] :=
             array['asignado', 'conductor_llego', 'en_curso', 'completado']::public.estado_viaje[];
begin
  perform privado.exigir_rol('conductor');

  select * into v_viaje from public.viajes
  where id = p_viaje_id and conductor_id = v_uid
  for update;
  if not found then
    perform privado.error('viaje_no_encontrado', 'El viaje no existe o no es tuyo');
  end if;

  if v_viaje.estado = 'cancelado' then
    perform privado.error('viaje_cancelado', 'El viaje fue cancelado');
  end if;

  -- Reintento de un paso que ya se aplicó (o de uno anterior): no hacer nada.
  if array_position(v_orden, v_viaje.estado) >= array_position(v_orden, p_estado) then
    return v_viaje;
  end if;

  if not (
       (v_viaje.estado = 'asignado'        and p_estado in ('conductor_llego', 'en_curso'))
    or (v_viaje.estado = 'conductor_llego' and p_estado = 'en_curso')
    or (v_viaje.estado = 'en_curso'        and p_estado = 'completado')
  ) then
    perform privado.error('transicion_invalida', 'Ese paso no corresponde al estado actual del viaje');
  end if;

  v_hora := least(greatest(coalesce(p_ocurrido_en, now()), v_viaje.asignado_en), now());

  update public.viajes
  set estado       = p_estado,
      llego_en     = case when p_estado = 'conductor_llego' then v_hora else llego_en end,
      iniciado_en  = case when p_estado = 'en_curso' then v_hora else iniciado_en end,
      terminado_en = case when p_estado = 'completado' then v_hora else terminado_en end
  where id = p_viaje_id
  returning * into v_viaje;

  if p_estado = 'completado' then
    update public.conductor_estado
    set estado = 'disponible'
    where conductor_id = v_uid and estado = 'ocupado';
  end if;

  return v_viaje;
end;
$$;

-- ---------------------------------------------------------------------
-- Cancelar (pasajero, conductor o despacho)
-- · Pasajero / despacho: el viaje queda cancelado.
-- · Conductor: "suelta" el viaje; vuelve a buscar otro conductor
--   (y a él ya no se le ofrece).
-- ---------------------------------------------------------------------
create function public.cancelar_viaje(p_viaje_id uuid, p_motivo text default null)
returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_uid    uuid := auth.uid();
  v_rol    public.rol_usuario := public.rol_actual();
  v_viaje  public.viajes;
begin
  perform privado.exigir_rol('pasajero', 'conductor', 'despachador', 'admin');

  select * into v_viaje from public.viajes where id = p_viaje_id for update;
  if not found
     or (v_rol = 'pasajero' and v_viaje.pasajero_id is distinct from v_uid)
     or (v_rol = 'conductor' and v_viaje.conductor_id is distinct from v_uid)
     or (v_rol in ('despachador', 'admin') and not public.puede_ver_sitio(v_viaje.sitio_id)) then
    perform privado.error('viaje_no_encontrado', 'El viaje no existe');
  end if;

  if v_viaje.estado = 'cancelado' then
    return v_viaje;
  end if;

  -- El conductor suelta el viaje.
  if v_rol = 'conductor' then
    if v_viaje.estado not in ('asignado', 'conductor_llego') then
      perform privado.error('no_cancelable', 'El viaje ya inició; avisa al despacho');
    end if;

    insert into public.ofertas_viaje (viaje_id, conductor_id, respuesta, respondido_en)
    values (p_viaje_id, v_uid, 'rechazada', now())
    on conflict (viaje_id, conductor_id) do update
      set respuesta = 'rechazada', respondido_en = now();

    update public.viajes
    set estado = 'buscando', conductor_id = null, unidad_id = null, sitio_id = null,
        asignado_en = null, llego_en = null
    where id = p_viaje_id
    returning * into v_viaje;

    update public.conductor_estado set estado = 'disponible'
    where conductor_id = v_uid and estado = 'ocupado';

    perform privado.ofrecer_siguiente(p_viaje_id);
    return v_viaje;
  end if;

  if v_viaje.estado = 'completado'
     or (v_viaje.estado = 'en_curso' and v_rol = 'pasajero') then
    perform privado.error('no_cancelable', 'Este viaje ya no se puede cancelar');
  end if;

  update public.ofertas_viaje
  set respuesta = 'expirada', respondido_en = now()
  where viaje_id = p_viaje_id and respuesta = 'pendiente';

  update public.viajes
  set estado = 'cancelado', cancelado_en = now(), cancelado_por = v_uid,
      motivo_cancelacion = nullif(trim(p_motivo), '')
  where id = p_viaje_id
  returning * into v_viaje;

  if v_viaje.conductor_id is not null then
    update public.conductor_estado set estado = 'disponible'
    where conductor_id = v_viaje.conductor_id and estado = 'ocupado';
  end if;

  return v_viaje;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC del despacho
-- ---------------------------------------------------------------------
-- Pedido por teléfono. Si se indica p_conductor_id, queda asignado de
-- inmediato; si no, entra a la asignación automática.
create function public.crear_viaje_telefonico(
  p_client_request_id   uuid,
  p_contacto_nombre     text,
  p_contacto_telefono   text,
  p_origen_lat          double precision,
  p_origen_lng          double precision,
  p_origen_referencia   text default null,
  p_destino_lat         double precision default null,
  p_destino_lng         double precision default null,
  p_destino_referencia  text default null,
  p_conductor_id        uuid default null
) returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_tel    public.telefono_mx := public.normalizar_telefono(p_contacto_telefono);
  v_viaje  public.viajes;
begin
  perform privado.exigir_rol('despachador', 'admin');
  if p_client_request_id is null then
    perform privado.error('solicitud_invalida', 'Falta el identificador de la solicitud');
  end if;

  select * into v_viaje from public.viajes where client_request_id = p_client_request_id;
  if found then
    return v_viaje;
  end if;

  if privado.telefono_bloqueado(v_tel) then
    perform privado.error('telefono_bloqueado', 'Este número está bloqueado');
  end if;

  v_viaje := privado.insertar_viaje(
    'telefono', p_client_request_id, null, p_contacto_nombre, v_tel,
    p_origen_lat, p_origen_lng, p_origen_referencia,
    p_destino_lat, p_destino_lng, p_destino_referencia);

  if p_conductor_id is not null then
    return public.asignar_viaje(v_viaje.id, p_conductor_id);
  end if;

  perform privado.ofrecer_siguiente(v_viaje.id);
  return v_viaje;
end;
$$;

-- Asignación directa por el despacho (sin esperar aceptación).
create function public.asignar_viaje(p_viaje_id uuid, p_conductor_id uuid)
returns public.viajes
language plpgsql security definer set search_path = '' as $$
declare
  v_viaje  public.viajes;
begin
  perform privado.exigir_rol('despachador', 'admin');

  select * into v_viaje from public.viajes where id = p_viaje_id for update;
  if not found or not public.puede_ver_sitio(v_viaje.sitio_id) then
    perform privado.error('viaje_no_encontrado', 'El viaje no existe');
  end if;

  if v_viaje.estado = 'asignado' and v_viaje.conductor_id = p_conductor_id then
    return v_viaje;
  end if;
  if v_viaje.estado not in ('buscando', 'sin_conductor') then
    perform privado.error('no_asignable', 'El viaje ya tiene conductor o terminó');
  end if;

  if not exists (select 1 from public.conductores
                 where perfil_id = p_conductor_id and public.puede_ver_sitio(sitio_id)) then
    perform privado.error('conductor_no_disponible', 'El conductor no está disponible');
  end if;

  -- Si el conductor está viendo otra oferta, esperar a que responda (máx. 20 s).
  if exists (select 1 from public.ofertas_viaje
             where conductor_id = p_conductor_id and respuesta = 'pendiente'
               and viaje_id <> p_viaje_id) then
    perform privado.error('conductor_con_oferta',
      'El conductor está respondiendo otra oferta; intenta en unos segundos');
  end if;

  return privado.asignar(p_viaje_id, p_conductor_id);
end;
$$;

-- ---------------------------------------------------------------------
-- Permisos de las funciones
-- ---------------------------------------------------------------------
revoke all on all functions in schema privado from public, anon, authenticated;

revoke execute on function
  public.solicitar_viaje(uuid, double precision, double precision, text, double precision, double precision, text),
  public.mi_viaje_activo(),
  public.cambiar_disponibilidad(public.estado_conductor, bigint),
  public.mi_oferta_pendiente(),
  public.responder_oferta(bigint, boolean),
  public.mi_viaje_activo_conductor(),
  public.avanzar_viaje(uuid, public.estado_viaje, timestamptz),
  public.cancelar_viaje(uuid, text),
  public.crear_viaje_telefonico(uuid, text, text, double precision, double precision, text, double precision, double precision, text, uuid),
  public.asignar_viaje(uuid, uuid)
from public, anon;

grant execute on function
  public.solicitar_viaje(uuid, double precision, double precision, text, double precision, double precision, text),
  public.mi_viaje_activo(),
  public.cambiar_disponibilidad(public.estado_conductor, bigint),
  public.mi_oferta_pendiente(),
  public.responder_oferta(bigint, boolean),
  public.mi_viaje_activo_conductor(),
  public.avanzar_viaje(uuid, public.estado_viaje, timestamptz),
  public.cancelar_viaje(uuid, text),
  public.crear_viaje_telefonico(uuid, text, text, double precision, double precision, text, double precision, double precision, text, uuid),
  public.asignar_viaje(uuid, uuid)
to authenticated;

-- ---------------------------------------------------------------------
-- Realtime: las apps se suscriben a cambios (respetando RLS)
--   · pasajero: su viaje (viajes) y la ubicación de su taxi (conductor_estado)
--   · conductor: sus ofertas (ofertas_viaje) y su viaje (viajes)
--   · panel: todo lo de su sitio
-- ---------------------------------------------------------------------
alter publication supabase_realtime
  add table public.viajes, public.ofertas_viaje, public.conductor_estado;

-- ---------------------------------------------------------------------
-- Asignación automática cada 5 segundos
-- ---------------------------------------------------------------------
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'procesar-ofertas-vencidas',
  '5 seconds',
  $$ select privado.procesar_ofertas_vencidas() $$
);
