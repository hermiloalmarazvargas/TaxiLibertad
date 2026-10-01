// Restablece la contraseña de un conductor o despachador. Solo para administradores.
//
// POST /functions/v1/restablecer-password
// Authorization: Bearer <token del admin>
// { "perfil_id": "<uuid>" }
//
// 200 → { usuario, password }   (la nueva contraseña se muestra una sola vez)
// 4xx → { error, codigo }
import '@supabase/functions-js/edge-runtime.d.ts';
import { generarPassword } from '../_shared/cuentas.ts';
import { corsHeaders, error, json } from '../_shared/http.ts';
import { clienteAdmin, perfilDeQuienLlama } from '../_shared/supabase.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return error(405, 'metodo_no_permitido', 'Método no permitido');

  const admin = clienteAdmin();

  const quien = await perfilDeQuienLlama(admin, req);
  if (!quien) return error(401, 'sesion_invalida', 'Tu sesión expiró. Vuelve a iniciar sesión.');
  if (quien.rol !== 'admin') {
    return error(403, 'sin_permiso', 'Solo un administrador puede restablecer contraseñas');
  }

  let perfilId: unknown;
  try {
    ({ perfil_id: perfilId } = await req.json());
  } catch {
    return error(400, 'entrada_invalida', 'La solicitud no es válida');
  }
  if (typeof perfilId !== 'string' || !UUID.test(perfilId)) {
    return error(400, 'entrada_invalida', 'Falta indicar la cuenta');
  }

  // Los pasajeros no tienen contraseña, y la de otro admin no se toca desde aquí.
  const { data: perfil } = await admin
    .from('perfiles')
    .select('usuario, rol')
    .eq('id', perfilId)
    .maybeSingle();
  if (!perfil || !['conductor', 'despachador'].includes(perfil.rol)) {
    return error(404, 'cuenta_no_encontrada', 'La cuenta no existe o no se puede restablecer');
  }

  const password = generarPassword();
  const { error: errorAuth } = await admin.auth.admin.updateUserById(perfilId, { password });
  if (errorAuth) {
    console.error('updateUserById', errorAuth);
    return error(500, 'error_interno', 'No se pudo restablecer la contraseña');
  }

  return json(200, { usuario: perfil.usuario, password });
});
