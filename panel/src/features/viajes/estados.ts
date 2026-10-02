import type { ColorInsignia } from '../../componentes/Avisos'
import type { EstadoViaje } from './api'

// Cómo se muestra cada estado: texto, color de insignia y color en el mapa.
export const ESTADO: Record<EstadoViaje, { texto: string; insignia: ColorInsignia; mapa: string }> = {
  sin_conductor: { texto: 'Sin conductor', insignia: 'rojo', mapa: '#dc2626' },
  buscando: { texto: 'Buscando taxi', insignia: 'ambar', mapa: '#d97706' },
  asignado: { texto: 'Taxi en camino', insignia: 'verde', mapa: '#2563eb' },
  conductor_llego: { texto: 'El taxi llegó', insignia: 'verde', mapa: '#7c3aed' },
  en_curso: { texto: 'En viaje', insignia: 'verde', mapa: '#16a34a' },
  completado: { texto: 'Completado', insignia: 'gris', mapa: '#64748b' },
  cancelado: { texto: 'Cancelado', insignia: 'gris', mapa: '#64748b' },
}
