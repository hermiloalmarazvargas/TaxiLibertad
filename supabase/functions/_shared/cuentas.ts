// Reglas de las cuentas del personal, compartidas por las Edge Functions.

// Debe coincidir con el dominio que usan el panel y las apps al iniciar sesión.
export const DOMINIO_USUARIOS = 'usuarios.taxi.internal';

export const correoDeUsuario = (usuario: string) => `${usuario}@${DOMINIO_USUARIOS}`;

// Contraseña fácil de dictar: sin caracteres que se confunden (0/O, 1/l/I),
// con al menos una letra y un dígito (regla de contraseñas de Auth).
export function generarPassword(largo = 10): string {
  const letras = 'abcdefghjkmnpqrstuvwxyz';
  const digitos = '23456789';
  const todos = letras + digitos;
  const azar = crypto.getRandomValues(new Uint32Array(largo * 2));
  const chars = Array.from(azar.slice(0, largo), (n) => todos[n % todos.length]);
  chars[0] = letras[azar[0] % letras.length];
  chars[1] = digitos[azar[1] % digitos.length];
  for (let i = largo - 1; i > 0; i--) {
    const j = azar[largo + i] % (i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}
