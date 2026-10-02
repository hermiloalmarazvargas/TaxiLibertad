-- =====================================================================
-- Corrección para reportes: cuando un conductor "suelta" un viaje, su
-- oferta ya NO se cambia a 'rechazada'. Antes, una oferta aceptada y luego
-- soltada quedaba como rechazada: los reportes perdían la aceptación y
-- contaban un rechazo que no ocurrió.
--   · Si ya tenía una oferta (aceptada), se conserva tal cual; esa fila
--     basta para que no se le vuelva a ofrecer el viaje.
--   · Si el despacho se lo asignó directo (sin oferta), se registra una
--     fila 'soltada' solo para excluirlo. No cuenta como oferta.
-- El número de viajes soltados sale de viaje_eventos.
-- =====================================================================

alter type public.respuesta_oferta add value 'soltada';

create or replace function public.cancelar_viaje(p_viaje_id uuid, p_motivo text default null)
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

    -- Excluirlo de este viaje sin alterar su oferta original (si la hay).
    insert into public.ofertas_viaje (viaje_id, conductor_id, respuesta, respondido_en)
    values (p_viaje_id, v_uid, 'soltada', now())
    on conflict (viaje_id, conductor_id) do nothing;

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
