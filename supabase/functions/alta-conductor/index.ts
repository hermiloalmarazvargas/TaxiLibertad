// Alta de un conductor desde el panel. Solo para administradores.
//
// POST /functions/v1/alta-conductor
// Authorization: Bearer <token del admin>
// { "nombre": "Juan Pérez", "usuario": "juan.perez", "sitio_id": 1,
//   "telefono": "951 123 4567", "password": "opcional" }
//
// 201 → { id, usuario, password? }   (password solo si se generó; se muestra una vez)
// 4xx → { error, codigo }
import '@supabase/functions-js/edge-runtime.d.ts';
import { corsHeaders, error, json } from '../_shared/http.ts';
import { clienteAdmin, perfilDeQuienLlama } from '../_shared/supabase.ts';

// Debe coincidir con el dominio que usan las apps al iniciar sesión.
const DOMINIO_USUARIOS = 'usuarios.taxi.internal';
const USUARIO_VALIDO = /^[a-z0-9][a-z0-9._]{2,29}$/;

type Entrada = {
  nombre?: unknown;
  usuario?: unknown;
  sitio_id?: unknown;
  telefono?: unknown;
  password?: unknown;
};

function validar(e: Entrada): string[] {
  const errores: string[] = [];
  if (typeof e.nombre !== 'string' || e.nombre.trim().length < 2 || e.nombre.trim().length > 80) {
    errores.push('El nombre debe tener entre 2 y 80 caracteres');
  }
  if (typeof e.usuario !== 'string' || !USUARIO_VALIDO.test(e.usuario)) {
    errores.push('El usuario debe tener de 3 a 30 caracteres: minúsculas, números, punto o guion bajo');
  }
  if (!Number.isInteger(e.sitio_id)) {
    errores.push('Elige el sitio');
  }
  if (e.telefono != null && typeof e.telefono !== 'string') {
    errores.push('El teléfono no es válido');
  }
  if (e.password != null && (typeof e.password !== 'string' || e.password.length < 8)) {
    errores.push('La contraseña debe tener al menos 8 caracteres, con letras y números');
  }
  return errores;
}

// Sin caracteres que se confunden al dictarlos (0/O, 1/l/I).
function generarPassword(largo = 10): string {
  const letras = 'abcdefghjkmnpqrstuvwxyz';
  const digitos = '23456789';
  const todos = letras + digitos;
  const azar = crypto.getRandomValues(new Uint32Array(largo * 2));
  const chars = Array.from(azar.slice(0, largo), (n) => todos[n % todos.length]);
  // Garantiza al menos una letra y un dígito (regla de contraseñas de Auth).
  chars[0] = letras[azar[0] % letras.length];
  chars[1] = digitos[azar[1] % digitos.length];
  for (let i = largo - 1; i > 0; i--) {
    const j = azar[largo + i] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return error(405, 'metodo_no_permitido', 'Método no permitido');

  const admin = clienteAdmin();

  const quien = await perfilDeQuienLlama(admin, req);
  if (!quien) return error(401, 'sesion_invalida', 'Tu sesión expiró. Vuelve a iniciar sesión.');
  if (quien.rol !== 'admin') {
    return error(403, 'sin_permiso', 'Solo un administrador puede dar de alta conductores');
  }

  let entrada: Entrada;
  try {
    entrada = await req.json();
  } catch {
    return error(400, 'entrada_invalida', 'La solicitud no es válida');
  }
  const errores = validar(entrada);
  if (errores.length) return error(400, 'entrada_invalida', errores.join('. '));

  const usuario = entrada.usuario as string;
  const passwordGenerada = entrada.password == null;
  const password = passwordGenerada ? generarPassword() : (entrada.password as string);

  const { data: creado, error: errorAuth } = await admin.auth.admin.createUser({
    email: `${usuario}@${DOMINIO_USUARIOS}`,
    password,
    email_confirm: true,
    // Marca que exige el hook before_user_created para permitir la cuenta.
    app_metadata: { alta: 'admin' },
  });
  if (errorAuth?.code === 'email_exists') {
    return error(409, 'usuario_existe', `El usuario "${usuario}" ya existe`);
  }
  if (errorAuth?.code === 'weak_password') {
    return error(400, 'password_debil', 'La contraseña debe tener al menos 8 caracteres, con letras y números');
  }
  if (errorAuth || !creado.user) {
    console.error('createUser', errorAuth);
    return error(500, 'error_interno', 'No se pudo crear la cuenta');
  }

  const { error: errorPerfil } = await admin.rpc('crear_perfil_conductor', {
    p_user_id: creado.user.id,
    p_nombre: entrada.nombre,
    p_usuario: usuario,
    p_telefono: entrada.telefono ?? null,
    p_sitio_id: entrada.sitio_id,
  });

  if (errorPerfil) {
    // Sin perfil la cuenta no sirve: se borra para poder reintentar.
    await admin.auth.admin.deleteUser(creado.user.id);
    if (errorPerfil.hint === 'sitio_invalido' || errorPerfil.hint === 'telefono_invalido') {
      return error(400, errorPerfil.hint, errorPerfil.message);
    }
    console.error('crear_perfil_conductor', errorPerfil);
    return error(500, 'error_interno', 'No se pudo crear la cuenta');
  }

  return json(201, {
    id: creado.user.id,
    usuario,
    ...(passwordGenerada ? { password } : {}),
  });
});
