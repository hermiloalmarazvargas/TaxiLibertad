-- =====================================================================
-- Ofertas ignoradas
-- Si un conductor deja VENCER 3 ofertas seguidas, pasa a fuera de servicio
-- con motivo "sin_respuesta" y recibe una notificación. Rechazar o aceptar
-- reinicia la cuenta. Una oferta retirada antes de vencer (el pasajero
-- canceló, el despacho asignó a otro) no cuenta.
-- =====================================================================

create function privado.max_ofertas_ignoradas() returns integer
language sql immutable as $$ select 3 $$;

-- ---------------------------------------------------------------------
-- Estado del conductor: contador y motivo de "fuera de servicio"
-- ---------------------------------------------------------------------
alter table public.conductor_estado
  add column ofertas_vencidas_seguidas smallint not null default 0,
  -- Solo con estado fuera_de_servicio: 'manual' (él mismo) o
  -- 'sin_respuesta' (dejó vencer ofertas). El despacho lo ve en el panel.
  add column motivo_fuera text check (motivo_fuera in ('manual', 'sin_respuesta')),
  add column fuera_desde timestamptz;

-- Mantiene motivo_fuera / fuera_desde / contador coherentes con el estado.
create function privado.conductor_estado_motivo() returns trigger
language plpgsql as $$
begin
  if new.estado is distinct from old.estado then
    if new.estado = 'fuera_de_servicio' then
      new.fuera_desde := now();
      -- Si quien hizo el cambio no indicó motivo, fue el propio conductor.
      if new.motivo_fuera is not distinct from old.motivo_fuera then
        new.motivo_fuera := 'manual';
      end if;
    else
      new.motivo_fuera := null;
      new.fuera_desde := null;
      if old.estado = 'fuera_de_servicio' then
        new.ofertas_vencidas_seguidas := 0;
      end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger conductor_estado_motivo
  before update of estado on public.conductor_estado
  for each row execute function privado.conductor_estado_motivo();

-- ---------------------------------------------------------------------
-- Notificaciones (bandeja de salida)
-- Hoy la app las recibe por Realtime; en la fase 5 una Edge Function
-- las enviará además por FCM y llenará enviada_en.
-- ---------------------------------------------------------------------
create table public.notificaciones (
  id          bigint generated always as identity primary key,
  perfil_id   uuid not null references public.perfiles (id) on delete cascade,
  tipo        text not null,
  titulo      text not null,
  cuerpo      text not null,
  datos       jsonb not null default '{}'::jsonb,
  creada_en   timestamptz not null default now(),
  enviada_en  timestamptz,
  leida_en    timestamptz
);

create index notificaciones_perfil_idx on public.notificaciones (perfil_id, creada_en desc);
create index notificaciones_por_enviar_idx on public.notificaciones (creada_en) where enviada_en is null;

alter table public.notificaciones enable row level security;

grant select on public.notificaciones to authenticated;
grant update (leida_en) on public.notificaciones to authenticated;

create policy "cada quien lee sus notificaciones"
  on public.notificaciones for select to authenticated
  using (perfil_id = (select auth.uid()));

create policy "cada quien marca sus notificaciones como leidas"
  on public.notificaciones for update to authenticated
  using (perfil_id = (select auth.uid()))
  with check (perfil_id = (select auth.uid()));

alter publication supabase_realtime add table public.notificaciones;

-- ---------------------------------------------------------------------
-- Conteo de ofertas ignoradas
-- ---------------------------------------------------------------------
create function privado.contar_respuesta_oferta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_vencidas  integer;
begin
  if new.respuesta in ('aceptada', 'rechazada') then
    update public.conductor_estado
    set ofertas_vencidas_seguidas = 0
    where conductor_id = new.conductor_id and ofertas_vencidas_seguidas <> 0;
    return null;
  end if;

  -- Solo cuenta si de verdad se le acabó el tiempo; si la retiraron
  -- antes (cancelación, asignación manual) no es culpa del conductor.
  if new.respuesta <> 'expirada' or new.expira_en > now() then
    return null;
  end if;

  update public.conductor_estado
  set ofertas_vencidas_seguidas = ofertas_vencidas_seguidas + 1
  where conductor_id = new.conductor_id
  returning ofertas_vencidas_seguidas into v_vencidas;

  if v_vencidas >= privado.max_ofertas_ignoradas() then
    update public.conductor_estado
    set estado = 'fuera_de_servicio', motivo_fuera = 'sin_respuesta',
        unidad_id = null, ubicacion = null, rumbo = null, precision_m = null
    where conductor_id = new.conductor_id and estado = 'disponible';

    if found then
      insert into public.notificaciones (perfil_id, tipo, titulo, cuerpo, datos)
      values (
        new.conductor_id,
        'fuera_por_no_responder',
        'Quedaste fuera de servicio',
        format('No respondiste %s ofertas seguidas. Cuando estés listo, vuelve a ponerte disponible.',
               privado.max_ofertas_ignoradas()),
        jsonb_build_object('ofertas_vencidas', v_vencidas)
      );
    end if;
  end if;

  return null;
end;
$$;

create trigger ofertas_viaje_contar_respuesta
  after update of respuesta on public.ofertas_viaje
  for each row
  when (old.respuesta = 'pendiente' and new.respuesta <> 'pendiente')
  execute function privado.contar_respuesta_oferta();

revoke all on all functions in schema privado from public, anon, authenticated;
