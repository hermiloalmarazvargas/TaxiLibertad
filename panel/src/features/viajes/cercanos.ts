import { metrosEntre } from '../../lib/distancia'
import { tieneSenal, type Punto, type Taxi } from './api'

// Taxis disponibles ordenados por cercanía a un punto. Los que no tienen
// señal reciente van al final (pueden estar sin datos o con el teléfono apagado).
export function taxisCercanos(taxis: Taxi[], punto: Punto, ahora: number) {
  return taxis
    .filter((t) => t.estado === 'disponible')
    .map((t) => ({
      taxi: t,
      senal: tieneSenal(t, ahora),
      metros: t.lat != null && t.lng != null ? metrosEntre(punto, { lat: t.lat, lng: t.lng }) : null,
    }))
    .sort((a, b) => Number(b.senal) - Number(a.senal) || (a.metros ?? Infinity) - (b.metros ?? Infinity))
}
