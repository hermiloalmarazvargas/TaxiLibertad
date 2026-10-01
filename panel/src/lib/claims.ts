import type { Rol } from '../auth/sesion'

type Claims = { rol?: Rol; sitio_id?: number }

// Lee los claims que agrega el custom_access_token_hook. Solo sirve para
// decidir qué mostrar en pantalla: la seguridad real la aplica RLS en la
// base de datos, que valida la firma del token.
export function leerClaims(accessToken: string): Claims {
  try {
    const payload = accessToken.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    const json = decodeURIComponent(
      Array.from(atob(payload), (c) => '%' + c.charCodeAt(0).toString(16).padStart(2, '0')).join(''),
    )
    return JSON.parse(json) as Claims
  } catch {
    return {}
  }
}
