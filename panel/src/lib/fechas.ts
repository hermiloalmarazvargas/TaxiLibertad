// Fechas "de calendario" (AAAA-MM-DD) en la hora de Oaxaca, la misma que
// usan los reportes en la base. Así "hoy" es el mismo día aunque la
// computadora del despacho tenga otra zona horaria configurada.
const ZONA = 'America/Mexico_City'

const formatoISO = new Intl.DateTimeFormat('en-CA', { timeZone: ZONA })

export function hoy(): string {
  return formatoISO.format(new Date())
}

export function sumarDias(fecha: string, dias: number): string {
  const d = new Date(`${fecha}T12:00:00Z`)
  d.setUTCDate(d.getUTCDate() + dias)
  return d.toISOString().slice(0, 10)
}

export function inicioDeMes(fecha: string): string {
  return `${fecha.slice(0, 8)}01`
}

const formatoDia = new Intl.DateTimeFormat('es-MX', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  timeZone: 'UTC',
})

// "2026-03-10" → "Mar 10 de mar" (solo la primera letra en mayúscula)
export function etiquetaDia(fecha: string): string {
  const texto = formatoDia.format(new Date(`${fecha}T12:00:00Z`)).replace(',', '')
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}
