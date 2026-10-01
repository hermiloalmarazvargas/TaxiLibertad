import { createClient, type SupabaseClient } from '@supabase/supabase-js';

// Cliente con service_role: ignora RLS. Solo existe dentro de la Edge
// Function; la llave nunca sale del servidor.
export function clienteAdmin(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

type Rol = 'pasajero' | 'conductor' | 'despachador' | 'admin';

// Verifica el token de quien llama y devuelve su perfil actual. Se consulta
// la tabla (no solo el JWT) para que una cuenta desactivada o un cambio de
// rol surtan efecto de inmediato.
export async function perfilDeQuienLlama(
  admin: SupabaseClient,
  req: Request,
): Promise<{ id: string; rol: Rol } | null> {
  const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return null;

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return null;

  const { data: perfil } = await admin
    .from('perfiles')
    .select('id, rol, activo')
    .eq('id', data.user.id)
    .maybeSingle();

  if (!perfil?.activo) return null;
  return { id: perfil.id, rol: perfil.rol };
}
