type Punto = { lat: number; lng: number }

// Distancia en línea recta (metros). Para ordenar taxis por cercanía basta;
// la distancia por calles la calcula Google Maps/Waze en la app del conductor.
export function metrosEntre(a: Punto, b: Punto): number {
  const R = 6_371_000
  const rad = (g: number) => (g * Math.PI) / 180
  const dLat = rad(b.lat - a.lat)
  const dLng = rad(b.lng - a.lng)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(h))
}

export function formatoDistancia(metros: number): string {
  return metros < 1000 ? `${Math.round(metros / 10) * 10} m` : `${(metros / 1000).toFixed(1)} km`
}

// "hace 3 min" / "hace 1 h 5 min"
export function hace(iso: string, ahora: number): string {
  const min = Math.max(0, Math.floor((ahora - new Date(iso).getTime()) / 60_000))
  if (min < 1) return 'hace un momento'
  if (min < 60) return `hace ${min} min`
  return `hace ${Math.floor(min / 60)} h ${min % 60} min`
}
