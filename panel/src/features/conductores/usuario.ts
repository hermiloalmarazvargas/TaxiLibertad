// "Juan Pérez López" → "juan.perez". Es solo una sugerencia; el admin la
// puede cambiar. Respeta la regla del servidor: 3–30 caracteres, [a-z0-9._].
export function sugerirUsuario(nombre: string): string {
  const palabras = nombre
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, '')
    .split(/\s+/)
    .filter(Boolean)

  if (palabras.length === 0) return ''
  const usuario = palabras.length === 1 ? palabras[0] : `${palabras[0]}.${palabras[1]}`
  return usuario.slice(0, 30)
}

export const USUARIO_VALIDO = /^[a-z0-9][a-z0-9._]{2,29}$/
