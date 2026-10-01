const hora = new Intl.DateTimeFormat('es-MX', { hour: 'numeric', minute: '2-digit' })
const fechaHora = new Intl.DateTimeFormat('es-MX', {
  day: 'numeric',
  month: 'short',
  hour: 'numeric',
  minute: '2-digit',
})

// "3:45 p.m." si es de hoy; "12 oct, 3:45 p.m." si es de otro día.
export function formatoHora(iso: string | null | undefined): string {
  if (!iso) return ''
  const fecha = new Date(iso)
  const esHoy = fecha.toDateString() === new Date().toDateString()
  return (esHoy ? hora : fechaHora).format(fecha)
}

// "951 123 4567" / "(951) 123-4567" / "+52 951…" → "+529511234567".
// Misma regla que public.normalizar_telefono en la base. null si no es válido.
export function normalizarTelefono(texto: string): string | null {
  let digitos = texto.replace(/\D/g, '')
  if (digitos.length === 12 && digitos.startsWith('52')) digitos = digitos.slice(2)
  return digitos.length === 10 ? `+52${digitos}` : null
}

// "+529511234567" → "951 123 4567"
export function formatoTelefono(telefono: string | null | undefined): string {
  const m = telefono?.match(/^\+52(\d{3})(\d{3})(\d{4})$/)
  return m ? `${m[1]} ${m[2]} ${m[3]}` : (telefono ?? '')
}
