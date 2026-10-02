import 'leaflet/dist/leaflet.css'
import type { Map as MapaLeaflet } from 'leaflet'
import { useEffect, type ReactNode } from 'react'
import { LayersControl, MapContainer, TileLayer, useMap } from 'react-leaflet'
import { CENTRO_MIAHUATLAN } from './constantes'

const KEY = import.meta.env.VITE_MAPTILER_KEY as string | undefined

const ATRIBUCION =
  '<a href="https://www.maptiler.com/copyright/" target="_blank">&copy; MapTiler</a> ' +
  '<a href="https://www.openstreetmap.org/copyright" target="_blank">&copy; OpenStreetMap</a>'

// Mosaicos de 256 px: los mismos que usará flutter_map en las apps.
const capa = (estilo: string, ext: string) =>
  `https://api.maptiler.com/maps/${estilo}/256/{z}/{x}/{y}.${ext}?key=${KEY}`

declare global {
  interface Window {
    // Solo en desarrollo: permite a las pruebas en navegador ubicar coordenadas.
    __mapa?: MapaLeaflet
  }
}

function ExponerParaPruebas() {
  const map = useMap()
  useEffect(() => {
    if (import.meta.env.DEV) window.__mapa = map
  }, [map])
  return null
}

type Props = {
  children?: ReactNode
  className?: string
  zoom?: number
}

export function MapaBase({ children, className = 'h-[32rem]', zoom = 14 }: Props) {
  if (!KEY) {
    return (
      <p className="rounded-lg bg-amber-50 p-4 text-amber-900 ring-1 ring-amber-200" role="alert">
        Falta VITE_MAPTILER_KEY en panel/.env.local; sin ella no se puede mostrar el mapa.
      </p>
    )
  }

  return (
    <MapContainer
      center={CENTRO_MIAHUATLAN}
      zoom={zoom}
      className={`w-full rounded-xl ring-1 ring-slate-200 ${className}`}
    >
      <LayersControl position="topright">
        <LayersControl.BaseLayer checked name="Mapa">
          <TileLayer url={capa('streets-v2', 'png')} attribution={ATRIBUCION} maxZoom={20} />
        </LayersControl.BaseLayer>
        {/* Satélite con nombres de calles: ayuda a ubicar casas sin dirección formal. */}
        <LayersControl.BaseLayer name="Satélite">
          <TileLayer url={capa('hybrid', 'jpg')} attribution={ATRIBUCION} maxZoom={20} />
        </LayersControl.BaseLayer>
      </LayersControl>
      <ExponerParaPruebas />
      {children}
    </MapContainer>
  )
}
