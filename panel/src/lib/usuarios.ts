// El personal inicia sesión con "usuario"; Auth necesita un correo, así que
// se usa uno interno que nadie ve. Debe coincidir con la Edge Function
// alta-conductor y con las apps.
const DOMINIO_USUARIOS = 'usuarios.taxi.internal'

export const correoDeUsuario = (usuario: string) =>
  `${usuario.trim().toLowerCase()}@${DOMINIO_USUARIOS}`
