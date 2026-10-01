-- =====================================================================
-- Fase 2: alta de conductores desde el panel
-- La Edge Function "alta-conductor" crea el usuario en Auth y luego llama
-- a esta función para crear perfil, conductor y estado en una sola
-- transacción. Solo la puede ejecutar service_role (la Edge Function).
-- =====================================================================

create function public.crear_perfil_conductor(
  p_user_id   uuid,
  p_nombre    text,
  p_usuario   text,
  p_telefono  text,
  p_sitio_id  bigint
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.sitios where id = p_sitio_id and activo) then
    perform privado.error('sitio_invalido', 'El sitio no existe o está inactivo');
  end if;

  insert into public.perfiles (id, rol, nombre, usuario, telefono)
  values (
    p_user_id, 'conductor', trim(p_nombre), p_usuario,
    case when nullif(trim(p_telefono), '') is not null then public.normalizar_telefono(p_telefono) end
  );

  insert into public.conductores (perfil_id, sitio_id) values (p_user_id, p_sitio_id);
  insert into public.conductor_estado (conductor_id) values (p_user_id);
end;
$$;

revoke execute on function public.crear_perfil_conductor(uuid, text, text, text, bigint)
  from public, anon, authenticated;
grant execute on function public.crear_perfil_conductor(uuid, text, text, text, bigint)
  to service_role;
