// Cliente de Supabase con la llave secreta (service role).
// SOLO para scripts que corren en la computadora del administrador.
// Esta llave jamás debe ir en las apps ni en el panel.
import { createClient } from '@supabase/supabase-js';

// Debe coincidir con el dominio que usan las apps para el inicio de sesión.
export const DOMINIO_USUARIOS = 'usuarios.taxi.internal';

export const correoDeUsuario = (usuario) => `${usuario}@${DOMINIO_USUARIOS}`;

export function crearClienteAdmin() {
  const url = process.env.SUPABASE_URL;
  const llave = process.env.SUPABASE_SECRET_KEY;
  if (!url || !llave) {
    throw new Error('Faltan SUPABASE_URL o SUPABASE_SECRET_KEY en .env (ver .env.example)');
  }
  return createClient(url, llave, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
