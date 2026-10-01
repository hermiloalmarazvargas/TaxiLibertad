// Convierte errores de Supabase en mensajes para mostrar al usuario.
// Las RPC y Edge Functions ya devuelven mensajes en español; aquí solo se
// traducen los errores genéricos de red y de Auth.
export function mensajeDeError(error: unknown): string {
  const mensaje =
    error instanceof Error
      ? error.message
      : typeof error === 'object' && error && 'message' in error
        ? String(error.message)
        : String(error ?? '')

  if (/invalid login credentials/i.test(mensaje)) return 'Usuario o contraseña incorrectos'
  if (/failed to fetch|network|load failed/i.test(mensaje)) {
    return 'Sin conexión con el servidor. Revisa tu internet e intenta de nuevo.'
  }
  return mensaje || 'Ocurrió un error inesperado'
}
