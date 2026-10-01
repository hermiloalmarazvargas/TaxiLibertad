-- =====================================================================
-- Fase 2: administrar conductores (desactivar / reactivar)
-- =====================================================================

-- Nuevo motivo de "fuera de servicio": el admin desactivó la cuenta.
alter table public.conductor_estado drop constraint conductor_estado_motivo_fuera_check;
alter table public.conductor_estado add constraint conductor_estado_motivo_fuera_check
  check (motivo_fuera in ('manual', 'sin_respuesta', 'desactivado'));

-- Una cuenta desactivada conserva su token hasta que vence (≈ 1 hora).
-- Para que la desactivación surta efecto de inmediato, toda RPC revisa
-- también que el perfil siga activo.
create or replace function privado.exigir_rol(variadic p_roles public.rol_usuario[]) returns void
language plpgsql stable set search_path = '' as $$
begin
  if public.rol_actual() is null
     or not (public.rol_actual() = any (p_roles))
     or not exists (select 1 from public.perfiles where id = auth.uid() and activo) then
    raise exception 'No tienes permiso para esta acción' using errcode = '42501';
  end if;
end;
$$;

revoke all on function privado.exigir_rol(public.rol_usuario[]) from public, anon, authenticated;

create function public.cambiar_activo_conductor(p_conductor_id uuid, p_activo boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_viaje_id uuid;
begin
  perform privado.exigir_rol('admin');

  if not exists (select 1 from public.conductores where perfil_id = p_conductor_id) then
    perform privado.error('conductor_no_encontrado', 'El conductor no existe');
  end if;

  if not p_activo then
    if exists (select 1 from public.viajes
               where conductor_id = p_conductor_id
                 and estado in ('asignado', 'conductor_llego', 'en_curso')) then
      perform privado.error('viaje_en_curso',
        'El conductor tiene un viaje en curso; desactívalo cuando termine');
    end if;

    -- Si estaba viendo una oferta, el viaje pasa al siguiente conductor.
    -- (Orden de bloqueo: primero el viaje.)
    select viaje_id into v_viaje_id
    from public.ofertas_viaje where conductor_id = p_conductor_id and respuesta = 'pendiente';
    if v_viaje_id is not null then
      perform 1 from public.viajes where id = v_viaje_id for update;
      update public.ofertas_viaje set respuesta = 'expirada', respondido_en = now()
      where conductor_id = p_conductor_id and respuesta = 'pendiente';
    end if;

    update public.conductor_estado
    set estado = 'fuera_de_servicio', motivo_fuera = 'desactivado',
        unidad_id = null, ubicacion = null, rumbo = null, precision_m = null
    where conductor_id = p_conductor_id and estado <> 'fuera_de_servicio';

    -- Si ya estaba fuera de servicio, solo se actualiza el motivo.
    update public.conductor_estado set motivo_fuera = 'desactivado'
    where conductor_id = p_conductor_id;
  else
    update public.conductor_estado set motivo_fuera = 'manual'
    where conductor_id = p_conductor_id and motivo_fuera = 'desactivado';
  end if;

  update public.perfiles set activo = p_activo where id = p_conductor_id;
  update public.conductores set activo = p_activo where perfil_id = p_conductor_id;

  if v_viaje_id is not null then
    perform privado.ofrecer_siguiente(v_viaje_id);
  end if;
end;
$$;

revoke execute on function public.cambiar_activo_conductor(uuid, boolean) from public, anon;
grant execute on function public.cambiar_activo_conductor(uuid, boolean) to authenticated;
