import { useEffect } from 'react'
import { CircleMarker, Polyline, Tooltip, useMap, useMapEvents } from 'react-leaflet'
import { MapaBase } from '../../componentes/mapa/MapaBase'
import { contactoDe, tieneSenal, type Punto, type Taxi, type Viaje } from './api'
import { ESTADO } from './estados'

export type ModoMarcar = 'origen' | 'destino' | null

type Props = {
  viajes: Viaje[]
  taxis: Taxi[]
  ahora: number
  seleccionado: string | null
  onSeleccionar: (id: string) => void
  // Formulario de viaje telefónico: qué punto se marca con el siguiente clic.
  modoMarcar: ModoMarcar
  origen: Punto | null
  destino: Punto | null
  onMarcar: (punto: Punto) => void
}

export function MapaViajes(props: Props) {
  const { viajes, taxis, ahora, seleccionado, onSeleccionar, origen, destino } = props

  return (
    <MapaBase className="h-[calc(100vh-12rem)] min-h-[28rem]" zoom={15}>
      <Clics {...props} />
      <IrASeleccionado viajes={viajes} seleccionado={seleccionado} />

      {taxis
        .filter((t) => t.lat != null && t.lng != null)
        .map((t) => {
          const senal = tieneSenal(t, ahora)
          const color = !senal ? '#94a3b8' : t.estado === 'disponible' ? '#16a34a' : '#d97706'
          return (
            <CircleMarker
              key={t.conductor_id}
              center={[t.lat!, t.lng!]}
              radius={9}
              pathOptions={{ color: '#0f172a', weight: 2, fillColor: color, fillOpacity: 1 }}
            >
              <Tooltip permanent direction="right" offset={[10, 0]} className="!px-1 !py-0 !text-xs !font-bold">
                {t.unidad?.numero_economico ?? '?'}
              </Tooltip>
            </CircleMarker>
          )
        })}

      {viajes.map((v) => {
        const elegido = v.id === seleccionado
        const color = ESTADO[v.estado].mapa
        return (
          <CircleMarker
            key={v.id}
            center={[v.origen_lat!, v.origen_lng!]}
            radius={elegido ? 14 : 11}
            pathOptions={{ color, weight: elegido ? 5 : 3, fillColor: '#ffffff', fillOpacity: 0.9 }}
            eventHandlers={{ click: () => onSeleccionar(v.id) }}
          >
            <Tooltip direction="top" offset={[0, -10]}>
              {ESTADO[v.estado].texto} · {contactoDe(v).nombre}
              {v.origen_referencia && ` · ${v.origen_referencia}`}
            </Tooltip>
          </CircleMarker>
        )
      })}

      {/* Ruta (línea recta) del viaje seleccionado hacia su destino. */}
      {viajes
        .filter((v) => v.id === seleccionado && v.destino_lat != null)
        .map((v) => (
          <Polyline
            key={`ruta-${v.id}`}
            positions={[
              [v.origen_lat!, v.origen_lng!],
              [v.destino_lat!, v.destino_lng!],
            ]}
            pathOptions={{ color: ESTADO[v.estado].mapa, dashArray: '8 8', weight: 3 }}
          />
        ))}

      {/* Puntos del viaje telefónico que se está capturando. */}
      {origen && (
        <CircleMarker center={[origen.lat, origen.lng]} radius={12} pathOptions={{ color: '#0f172a', weight: 4, fillColor: '#f59e0b', fillOpacity: 1 }}>
          <Tooltip permanent direction="top" offset={[0, -12]}>
            Origen
          </Tooltip>
        </CircleMarker>
      )}
      {destino && (
        <CircleMarker center={[destino.lat, destino.lng]} radius={12} pathOptions={{ color: '#0f172a', weight: 4, fillColor: '#0ea5e9', fillOpacity: 1 }}>
          <Tooltip permanent direction="top" offset={[0, -12]}>
            Destino
          </Tooltip>
        </CircleMarker>
      )}
      {origen && destino && (
        <Polyline
          positions={[
            [origen.lat, origen.lng],
            [destino.lat, destino.lng],
          ]}
          pathOptions={{ color: '#0f172a', dashArray: '8 8', weight: 3 }}
        />
      )}
    </MapaBase>
  )
}

function Clics({ modoMarcar, onMarcar }: Props) {
  const map = useMapEvents({
    click: (e) => {
      if (modoMarcar) onMarcar({ lat: e.latlng.lat, lng: e.latlng.lng })
    },
  })
  // Cursor en cruz mientras se espera un clic para marcar.
  useEffect(() => {
    map.getContainer().style.cursor = modoMarcar ? 'crosshair' : ''
  }, [map, modoMarcar])
  return null
}

function IrASeleccionado({ viajes, seleccionado }: { viajes: Viaje[]; seleccionado: string | null }) {
  const map = useMap()
  const viaje = viajes.find((v) => v.id === seleccionado)
  const lat = viaje?.origen_lat
  const lng = viaje?.origen_lng
  useEffect(() => {
    if (lat != null && lng != null) map.flyTo([lat, lng], Math.max(map.getZoom(), 16), { duration: 0.5 })
  }, [map, lat, lng])
  return null
}
