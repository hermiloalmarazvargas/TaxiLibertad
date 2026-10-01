import { Insignia, type ColorInsignia } from '../../componentes/Avisos'
import { formatoHora } from '../../lib/formato'
import type { Conductor } from './api'

// Igual que en el servidor (privado.segundos_ubicacion_vigente): sin
// ubicación reciente, el conductor no recibe ofertas automáticas.
const SEGUNDOS_UBICACION_VIGENTE = 60

type Props = { conductor: Conductor; ahora: number }

export function EstadoConductor({ conductor, ahora }: Props) {
  const e = conductor.estado
  if (!conductor.activo) return <Insignia color="oscuro">Cuenta desactivada</Insignia>
  if (!e) return <Insignia color="gris">Sin estado</Insignia>

  let color: ColorInsignia
  let texto: string
  const detalles: string[] = []

  if (e.estado === 'disponible') {
    color = 'verde'
    texto = 'Disponible'
    const ultima = e.ubicacion_en ? new Date(e.ubicacion_en).getTime() : 0
    if (ahora - ultima > SEGUNDOS_UBICACION_VIGENTE * 1000) {
      color = 'ambar'
      texto = 'Disponible · sin señal'
      detalles.push(e.ubicacion_en ? `Última ubicación ${formatoHora(e.ubicacion_en)}` : 'Sin ubicación')
    }
  } else if (e.estado === 'ocupado') {
    color = 'ambar'
    texto = 'Ocupado'
  } else if (e.motivo_fuera === 'sin_respuesta') {
    color = 'rojo'
    texto = 'Fuera: no respondió ofertas'
  } else {
    color = 'gris'
    texto = 'Fuera de servicio'
  }

  if (e.unidad?.numero_economico && e.estado !== 'fuera_de_servicio') {
    detalles.push(`Unidad ${e.unidad.numero_economico}`)
  }
  if (e.estado === 'fuera_de_servicio' && e.fuera_desde) {
    detalles.push(`Desde ${formatoHora(e.fuera_desde)}`)
  }
  if (e.estado === 'disponible' && e.ofertas_vencidas_seguidas > 0) {
    detalles.push(`${e.ofertas_vencidas_seguidas} oferta(s) sin responder`)
  }

  return (
    <div>
      <Insignia color={color}>{texto}</Insignia>
      {detalles.length > 0 && <p className="mt-1 text-sm text-slate-600">{detalles.join(' · ')}</p>}
    </div>
  )
}
