-- =====================================================================
-- Fase 2: reglas de catálogos (unidades y sitios)
-- Las altas y ediciones se hacen directo en las tablas (RLS: solo admin);
-- aquí solo van las reglas que la base debe garantizar.
-- =====================================================================

-- Una unidad en servicio (con un conductor disponible u ocupado) no se
-- puede desactivar ni mover de sitio: primero el conductor debe salir.
create function privado.validar_cambio_unidad() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (not new.activo or new.sitio_id <> old.sitio_id)
     and exists (select 1 from public.conductor_estado
                 where unidad_id = new.id and estado <> 'fuera_de_servicio') then
    perform privado.error('unidad_en_servicio',
      'La unidad está en servicio. Pide al conductor que salga de servicio primero.');
  end if;
  return new;
end;
$$;

create trigger unidades_validar_cambio
  before update of activo, sitio_id on public.unidades
  for each row execute function privado.validar_cambio_unidad();

-- Desactivar un sitio con conductores o unidades activos dejaría a esos
-- conductores sin poder elegir unidad: se exige moverlos o desactivarlos antes.
create function privado.validar_cambio_sitio() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.activo and not new.activo
     and (exists (select 1 from public.unidades where sitio_id = new.id and activo)
          or exists (select 1 from public.conductores where sitio_id = new.id and activo)) then
    perform privado.error('sitio_con_activos',
      'El sitio tiene unidades o conductores activos; desactívalos o muévelos primero.');
  end if;
  return new;
end;
$$;

create trigger sitios_validar_cambio
  before update of activo on public.sitios
  for each row execute function privado.validar_cambio_sitio();

revoke all on all functions in schema privado from public, anon, authenticated;
