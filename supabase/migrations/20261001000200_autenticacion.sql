-- =====================================================================
-- Fase 1 · Paso 2: autenticación y roles
--
-- · Pasajero: inicio de sesión anónimo + registrar_pasajero(nombre, teléfono).
--   Más adelante se puede vincular una verificación por SMS a la misma cuenta.
-- · Conductor / despachador / admin: usuario y contraseña, creados por el
--   admin (scripts/crear-usuario.mjs, después desde el panel). El "usuario"
--   se convierte en el correo interno <usuario>@usuarios.taxi.internal.
-- · El rol vive en public.perfiles y se copia al JWT con un Custom Access
--   Token Hook. NUNCA se toma de user_metadata (eso lo controla el cliente).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Usuario de inicio de sesión para el personal
-- ---------------------------------------------------------------------
alter table public.perfiles
  add column usuario text unique
    check (usuario ~ '^[a-z0-9][a-z0-9._]{2,29}$'),
  -- Pasajeros no tienen usuario; todo el personal sí.
  add constraint perfiles_usuario_segun_rol
    check ((rol = 'pasajero') = (usuario is null));

-- ---------------------------------------------------------------------
-- Teléfonos
-- ---------------------------------------------------------------------
-- Acepta "951 123 4567", "(951) 123-4567", "52 9511234567", "+52 951..."
-- y devuelve "+529511234567". Lanza error si no son 10 dígitos de México.
create or replace function public.normalizar_telefono(p_telefono text)
returns public.telefono_mx
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_digitos text := regexp_replace(coalesce(p_telefono, ''), '[^0-9]', '', 'g');
begin
  if length(v_digitos) = 12 and left(v_digitos, 2) = '52' then
    v_digitos := right(v_digitos, 10);
  end if;

  if length(v_digitos) <> 10 then
    raise exception 'El teléfono debe tener 10 dígitos'
      using errcode = '22023', hint = 'telefono_invalido';
  end if;

  return ('+52' || v_digitos)::public.telefono_mx;
end;
$$;

-- ---------------------------------------------------------------------
-- Rol de la sesión actual (lo usarán las políticas RLS del paso 3)
-- ---------------------------------------------------------------------
create or replace function public.rol_actual()
returns public.rol_usuario
language sql
stable
set search_path = ''
as $$
  select nullif(auth.jwt() ->> 'rol', '')::public.rol_usuario;
$$;

-- ---------------------------------------------------------------------
-- Custom Access Token Hook
-- Se ejecuta cada vez que Auth emite o renueva un token (≈ cada hora).
-- Por eso, desactivar una cuenta o bloquear un número tarda como máximo
-- lo que dura el token (jwt_expiry) en surtir efecto.
-- ---------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_claims  jsonb := event -> 'claims';
  v_perfil  record;
begin
  -- sitio_id: el del conductor (conductores) o el del despachador (perfiles).
  select p.rol,
         coalesce(c.sitio_id, p.sitio_id) as sitio_id,
         p.activo and coalesce(c.activo, true) as activo,
         p.telefono
    into v_perfil
  from public.perfiles p
  left join public.conductores c on c.perfil_id = p.id
  where p.id = (event ->> 'user_id')::uuid;

  -- Usuario sin perfil (pasajero anónimo que aún no se registra):
  -- token normal, sin rol. Las políticas RLS no le darán acceso a nada.
  if not found then
    return jsonb_build_object('claims', v_claims - 'rol' - 'sitio_id');
  end if;

  if not v_perfil.activo then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Tu cuenta está desactivada. Comunícate con el sitio.'));
  end if;

  if v_perfil.rol = 'pasajero' and exists (
    select 1 from public.telefonos_bloqueados b where b.telefono = v_perfil.telefono
  ) then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Este número no puede usar el servicio. Comunícate con el sitio.'));
  end if;

  v_claims := v_claims || jsonb_build_object('rol', v_perfil.rol);
  v_claims := case
    when v_perfil.sitio_id is null then v_claims - 'sitio_id'
    else v_claims || jsonb_build_object('sitio_id', v_perfil.sitio_id)
  end;

  return jsonb_build_object('claims', v_claims);
end;
$$;

-- Solo Auth (supabase_auth_admin) puede ejecutar el hook.
grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;

grant select on table public.perfiles, public.conductores, public.telefonos_bloqueados
  to supabase_auth_admin;

create policy "auth lee perfiles para el token"
  on public.perfiles for select to supabase_auth_admin using (true);

create policy "auth lee conductores para el token"
  on public.conductores for select to supabase_auth_admin using (true);

create policy "auth lee telefonos bloqueados para el token"
  on public.telefonos_bloqueados for select to supabase_auth_admin using (true);

-- ---------------------------------------------------------------------
-- Before User Created Hook
-- Nadie puede registrarse por su cuenta con correo/contraseña. Solo se
-- permiten: usuarios anónimos (pasajeros) y cuentas creadas por el admin
-- con app_metadata.alta = 'admin' (app_metadata solo se puede escribir con
-- la llave secreta; el cliente no puede falsificarlo).
-- ---------------------------------------------------------------------
create or replace function public.before_user_created_hook(event jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
begin
  if coalesce((event -> 'user' ->> 'is_anonymous')::boolean, false)
     or event -> 'user' -> 'app_metadata' ->> 'alta' = 'admin' then
    return '{}'::jsonb;
  end if;

  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403,
    'message', 'El registro no está permitido. Pide tu cuenta al administrador.'));
end;
$$;

grant execute on function public.before_user_created_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.before_user_created_hook(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Registro del pasajero (después de signInAnonymously)
-- La app debe llamar a refreshSession() al terminar para recibir el rol.
-- ---------------------------------------------------------------------
create or replace function public.registrar_pasajero(p_nombre text, p_telefono text)
returns public.perfiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_tel     public.telefono_mx := public.normalizar_telefono(p_telefono);
  v_perfil  public.perfiles;
begin
  if v_uid is null then
    raise exception 'Se requiere iniciar sesión' using errcode = '42501';
  end if;

  if exists (select 1 from public.telefonos_bloqueados b where b.telefono = v_tel) then
    raise exception 'Este número no puede usar el servicio. Comunícate con el sitio.'
      using errcode = '42501', hint = 'telefono_bloqueado';
  end if;

  insert into public.perfiles (id, rol, nombre, telefono)
  values (v_uid, 'pasajero', trim(p_nombre), v_tel)
  on conflict (id) do update
    set nombre = excluded.nombre,
        telefono = excluded.telefono,
        telefono_verificado = public.perfiles.telefono_verificado
                              and public.perfiles.telefono = excluded.telefono
    -- El personal no puede convertirse en pasajero por esta vía.
    where public.perfiles.rol = 'pasajero'
  returning * into v_perfil;

  if v_perfil.id is null then
    raise exception 'Esta cuenta no es de pasajero'
      using errcode = '42501', hint = 'no_es_pasajero';
  end if;

  return v_perfil;
end;
$$;

revoke execute on function public.registrar_pasajero(text, text) from public, anon;
grant execute on function public.registrar_pasajero(text, text) to authenticated;
