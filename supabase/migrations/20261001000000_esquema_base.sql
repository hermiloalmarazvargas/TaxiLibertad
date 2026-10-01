-- =====================================================================
-- Fase 1 · Paso 1: esquema base (tipos, tablas, índices)
-- Las políticas RLS se agregan en una migración posterior. Mientras tanto,
-- todas las tablas tienen RLS ACTIVADO y SIN políticas: nadie puede leer ni
-- escribir a través de la API (solo el rol postgres desde Studio/psql).
-- =====================================================================

create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type public.rol_usuario as enum ('pasajero', 'conductor', 'despachador', 'admin');

create type public.estado_conductor as enum ('fuera_de_servicio', 'disponible', 'ocupado');

create type public.estado_viaje as enum (
  'buscando',         -- se está ofreciendo a conductores
  'asignado',         -- un conductor va en camino al origen
  'conductor_llego',  -- el conductor está en el punto de origen
  'en_curso',         -- el pasajero va a bordo
  'completado',
  'cancelado',
  'sin_conductor'     -- nadie aceptó
);

create type public.canal_viaje as enum ('app', 'telefono');

create type public.respuesta_oferta as enum ('pendiente', 'aceptada', 'rechazada', 'expirada');

-- Teléfonos en formato E.164 de México: +52 seguido de 10 dígitos.
create domain public.telefono_mx as text
  check (value ~ '^\+52[0-9]{10}$');

-- ---------------------------------------------------------------------
-- Catálogos: sitios, unidades, zonas, tarifas
-- ---------------------------------------------------------------------
create table public.sitios (
  id         bigint generated always as identity primary key,
  nombre     text not null unique check (length(trim(nombre)) > 0),
  ubicacion  extensions.geography(Point, 4326),
  telefono   public.telefono_mx,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

create table public.unidades (
  id                bigint generated always as identity primary key,
  sitio_id          bigint not null references public.sitios (id),
  numero_economico  text not null check (length(trim(numero_economico)) > 0),
  placas            text not null unique check (placas = upper(trim(placas))),
  marca             text,
  modelo            text,
  color             text,
  activo            boolean not null default true,
  creado_en         timestamptz not null default now(),
  unique (sitio_id, numero_economico)
);

-- Si un punto cae en dos zonas que se traslapan, gana la de menor área
-- (la más específica). Ver public.zona_de().
create table public.zonas (
  id         bigint generated always as identity primary key,
  nombre     text not null unique check (length(trim(nombre)) > 0),
  poligono   extensions.geometry(MultiPolygon, 4326) not null
             check (extensions.st_isvalid(poligono)),
  color      text not null default '#2563eb' check (color ~ '^#[0-9a-fA-F]{6}$'),
  activa     boolean not null default true,
  creado_en  timestamptz not null default now()
);

create index zonas_poligono_gix on public.zonas using gist (poligono);

-- Tarifa por dirección: A→B y B→A son filas distintas, así pueden ser iguales
-- o diferentes. Sin fila = "tarifa a convenir".
create table public.tarifas (
  zona_origen_id   bigint not null references public.zonas (id) on delete cascade,
  zona_destino_id  bigint not null references public.zonas (id) on delete cascade,
  monto            numeric(8, 2) not null check (monto > 0),
  actualizado_por  uuid references auth.users (id) on delete set null,
  actualizado_en   timestamptz not null default now(),
  primary key (zona_origen_id, zona_destino_id)
);

-- ---------------------------------------------------------------------
-- Usuarios
-- ---------------------------------------------------------------------
create table public.perfiles (
  id                   uuid primary key references auth.users (id) on delete cascade,
  rol                  public.rol_usuario not null default 'pasajero',
  nombre               text not null check (length(trim(nombre)) between 2 and 80),
  -- Pasajeros: capturado sin verificar (sin SMS por ahora). Cuando se agregue
  -- verificación por SMS, telefono_verificado pasa a true.
  telefono             public.telefono_mx,
  telefono_verificado  boolean not null default false,
  -- Solo despachadores: null = despacho central (ve todos los sitios).
  sitio_id             bigint references public.sitios (id),
  activo               boolean not null default true,
  creado_en            timestamptz not null default now(),
  check (rol <> 'pasajero' or telefono is not null)
);

create index perfiles_telefono_idx on public.perfiles (telefono);

-- Números bloqueados por el despacho (pedidos falsos). Se revisa al crear
-- un viaje, tanto desde la app como por teléfono.
create table public.telefonos_bloqueados (
  telefono       public.telefono_mx primary key,
  motivo         text not null check (length(trim(motivo)) > 0),
  bloqueado_por  uuid references public.perfiles (id) on delete set null,
  bloqueado_en   timestamptz not null default now()
);

create table public.conductores (
  perfil_id  uuid primary key references public.perfiles (id) on delete cascade,
  sitio_id   bigint not null references public.sitios (id),
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

-- Estado "en vivo" del conductor: se actualiza cada pocos segundos.
-- Solo guarda la ÚLTIMA ubicación; no hay historial de recorridos.
create table public.conductor_estado (
  conductor_id    uuid primary key references public.conductores (perfil_id) on delete cascade,
  estado          public.estado_conductor not null default 'fuera_de_servicio',
  unidad_id       bigint references public.unidades (id),
  ubicacion       extensions.geography(Point, 4326),
  rumbo           smallint check (rumbo between 0 and 359),
  precision_m     real check (precision_m >= 0),
  ubicacion_en    timestamptz,
  actualizado_en  timestamptz not null default now(),
  -- Para estar disponible u ocupado hay que haber elegido unidad.
  check (estado = 'fuera_de_servicio' or unidad_id is not null)
);

-- Una unidad no puede estar en servicio con dos conductores a la vez.
create unique index conductor_estado_unidad_en_servicio_uq
  on public.conductor_estado (unidad_id)
  where estado <> 'fuera_de_servicio';

create index conductor_estado_disponibles_gix
  on public.conductor_estado using gist (ubicacion)
  where estado = 'disponible';

-- Tokens de Firebase Cloud Messaging (un usuario puede tener varios equipos).
create table public.dispositivos (
  id              bigint generated always as identity primary key,
  perfil_id       uuid not null references public.perfiles (id) on delete cascade,
  fcm_token       text not null unique,
  plataforma      text not null check (plataforma in ('android', 'ios', 'web')),
  actualizado_en  timestamptz not null default now()
);

create index dispositivos_perfil_idx on public.dispositivos (perfil_id);

-- ---------------------------------------------------------------------
-- Viajes
-- ---------------------------------------------------------------------
create table public.viajes (
  id                  uuid primary key default gen_random_uuid(),
  -- Lo genera la app antes de enviar; si se reintenta por falta de señal,
  -- el servidor reconoce el duplicado y no crea dos viajes.
  client_request_id   uuid unique,
  canal               public.canal_viaje not null,
  pasajero_id         uuid references public.perfiles (id) on delete set null,
  creado_por          uuid references public.perfiles (id) on delete set null,
  -- Solo viajes por teléfono (canal = 'telefono').
  contacto_nombre     text check (length(contacto_nombre) <= 80),
  contacto_telefono   public.telefono_mx,

  origen              extensions.geography(Point, 4326) not null,
  origen_referencia   text check (length(origen_referencia) <= 200),
  destino             extensions.geography(Point, 4326),
  destino_referencia  text check (length(destino_referencia) <= 200),
  zona_origen_id      bigint references public.zonas (id) on delete set null,
  zona_destino_id     bigint references public.zonas (id) on delete set null,
  -- Copia de la tarifa al momento de pedir. null = "a convenir".
  tarifa_monto        numeric(8, 2) check (tarifa_monto > 0),

  estado              public.estado_viaje not null default 'buscando',
  sitio_id            bigint references public.sitios (id),
  conductor_id        uuid references public.conductores (perfil_id),
  unidad_id           bigint references public.unidades (id),

  solicitado_en       timestamptz not null default now(),
  asignado_en         timestamptz,
  llego_en            timestamptz,
  iniciado_en         timestamptz,
  terminado_en        timestamptz,
  cancelado_en        timestamptz,
  cancelado_por       uuid references public.perfiles (id) on delete set null,
  motivo_cancelacion  text check (length(motivo_cancelacion) <= 200),

  check (
    estado not in ('asignado', 'conductor_llego', 'en_curso', 'completado')
    or (conductor_id is not null and unidad_id is not null)
  )
);

-- Un conductor (y una unidad) solo puede tener un viaje activo a la vez.
create unique index viajes_conductor_activo_uq
  on public.viajes (conductor_id)
  where estado in ('asignado', 'conductor_llego', 'en_curso');

create unique index viajes_unidad_activa_uq
  on public.viajes (unidad_id)
  where estado in ('asignado', 'conductor_llego', 'en_curso');

create index viajes_activos_idx
  on public.viajes (estado)
  where estado in ('buscando', 'asignado', 'conductor_llego', 'en_curso');

create index viajes_pasajero_idx on public.viajes (pasajero_id, solicitado_en desc);
create index viajes_conductor_idx on public.viajes (conductor_id, solicitado_en desc);
create index viajes_solicitado_idx on public.viajes (solicitado_en);

create table public.ofertas_viaje (
  id             bigint generated always as identity primary key,
  viaje_id       uuid not null references public.viajes (id) on delete cascade,
  conductor_id   uuid not null references public.conductores (perfil_id) on delete cascade,
  distancia_m    integer check (distancia_m >= 0),
  ofrecido_en    timestamptz not null default now(),
  expira_en      timestamptz not null default now() + interval '20 seconds',
  respuesta      public.respuesta_oferta not null default 'pendiente',
  respondido_en  timestamptz,
  -- No se vuelve a ofrecer el mismo viaje a quien ya lo vio.
  unique (viaje_id, conductor_id)
);

-- Un viaje se ofrece a un conductor a la vez, y un conductor ve una oferta a la vez.
create unique index ofertas_pendiente_por_viaje_uq
  on public.ofertas_viaje (viaje_id) where respuesta = 'pendiente';

create unique index ofertas_pendiente_por_conductor_uq
  on public.ofertas_viaje (conductor_id) where respuesta = 'pendiente';

create index ofertas_por_expirar_idx
  on public.ofertas_viaje (expira_en) where respuesta = 'pendiente';

-- Bitácora de cambios de estado (reportes y aclaraciones).
create table public.viaje_eventos (
  id               bigint generated always as identity primary key,
  viaje_id         uuid not null references public.viajes (id) on delete cascade,
  estado_anterior  public.estado_viaje,
  estado_nuevo     public.estado_viaje not null,
  actor_id         uuid references public.perfiles (id) on delete set null,
  -- Hora en que ocurrió en el teléfono (puede llegar tarde si no había señal).
  ocurrido_en      timestamptz not null default now(),
  registrado_en    timestamptz not null default now()
);

create index viaje_eventos_viaje_idx on public.viaje_eventos (viaje_id, ocurrido_en);

-- ---------------------------------------------------------------------
-- RLS activado en todo (sin políticas todavía = acceso denegado por la API)
-- ---------------------------------------------------------------------
alter table public.sitios               enable row level security;
alter table public.unidades             enable row level security;
alter table public.zonas                enable row level security;
alter table public.tarifas              enable row level security;
alter table public.perfiles             enable row level security;
alter table public.telefonos_bloqueados enable row level security;
alter table public.conductores          enable row level security;
alter table public.conductor_estado     enable row level security;
alter table public.dispositivos         enable row level security;
alter table public.viajes               enable row level security;
alter table public.ofertas_viaje        enable row level security;
alter table public.viaje_eventos        enable row level security;
