import type { GeoJSON as CapaGeoJSON } from 'leaflet'
import type { MultiPolygon, Polygon } from 'geojson'
import { useEffect, useRef, useState, type FormEvent } from 'react'
import { GeoJSON, Tooltip, useMap } from 'react-leaflet'
import { Insignia, MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo } from '../../componentes/Campo'
import L from '../../componentes/mapa/geoman'
import { MapaBase } from '../../componentes/mapa/MapaBase'
import { Modal } from '../../componentes/Modal'
import { mensajeDeError } from '../../lib/errores'
import { useCambiarActivaZona, useGuardarZona, useZonas, type Zona } from './api'

type Modo = { tipo: 'ver' } | { tipo: 'dibujar' } | { tipo: 'forma'; zona: Zona }
type Formulario = { zona?: Zona; forma?: Polygon | MultiPolygon }

const COLORES = ['#dc2626', '#2563eb', '#16a34a', '#9333ea', '#ea580c', '#0891b2', '#ca8a04', '#db2777']

export function EditorZonas() {
  const zonas = useZonas()
  const guardar = useGuardarZona()
  const cambiarActiva = useCambiarActivaZona()
  const [modo, setModo] = useState<Modo>({ tipo: 'ver' })
  const [formulario, setFormulario] = useState<Formulario | null>(null)
  const capaEditada = useRef<CapaGeoJSON | null>(null)

  const lista = zonas.data ?? []
  const editandoId = modo.tipo === 'forma' ? modo.zona.id : null

  function guardarForma() {
    if (modo.tipo !== 'forma' || !capaEditada.current) return
    const coleccion = capaEditada.current.toGeoJSON() as GeoJSON.FeatureCollection
    const forma = coleccion.features[0].geometry as Polygon | MultiPolygon
    guardar.mutate(
      { id: modo.zona.id, nombre: modo.zona.nombre, color: modo.zona.color, forma },
      { onSuccess: () => setModo({ tipo: 'ver' }) },
    )
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
      <div className="space-y-3">
        <Instrucciones modo={modo} />
        <MapaBase className="h-[36rem]">
          {lista
            .filter((z) => z.id !== editandoId)
            .map((z) => (
              <GeoJSON
                // La clave cambia con la forma para que Leaflet la vuelva a dibujar.
                key={`${z.id}-${z.color}-${z.activa}-${JSON.stringify(z.poligono.coordinates).length}`}
                data={z.poligono}
                style={{
                  color: z.activa ? z.color : '#64748b',
                  weight: 2,
                  fillOpacity: z.activa ? 0.2 : 0.05,
                  dashArray: z.activa ? undefined : '6 6',
                }}
              >
                <Tooltip sticky>{z.nombre}</Tooltip>
              </GeoJSON>
            ))}
          <AjustarVista zonas={lista} />
          <Dibujo
            activo={modo.tipo === 'dibujar'}
            onTerminado={(forma) => {
              setModo({ tipo: 'ver' })
              setFormulario({ forma })
            }}
          />
          {modo.tipo === 'forma' && (
            <EdicionForma zona={modo.zona} onCapa={(capa) => (capaEditada.current = capa)} />
          )}
        </MapaBase>
      </div>

      <aside className="space-y-4">
        {modo.tipo === 'ver' && (
          <Boton className="w-full" onClick={() => setModo({ tipo: 'dibujar' })}>
            Dibujar zona nueva
          </Boton>
        )}
        {modo.tipo === 'dibujar' && (
          <Boton variante="secundario" className="w-full" onClick={() => setModo({ tipo: 'ver' })}>
            Cancelar dibujo
          </Boton>
        )}
        {modo.tipo === 'forma' && (
          <div className="space-y-2 rounded-xl bg-amber-50 p-4 ring-1 ring-amber-200">
            <p className="font-semibold">Editando la forma de «{modo.zona.nombre}»</p>
            <MensajeError>{guardar.error && mensajeDeError(guardar.error)}</MensajeError>
            <div className="flex flex-wrap gap-2">
              <Boton onClick={guardarForma} disabled={guardar.isPending}>
                Guardar forma
              </Boton>
              <Boton variante="secundario" onClick={() => setModo({ tipo: 'ver' })}>
                Cancelar
              </Boton>
            </div>
          </div>
        )}

        <MensajeError>
          {(zonas.error && mensajeDeError(zonas.error)) || (cambiarActiva.error && mensajeDeError(cambiarActiva.error))}
        </MensajeError>

        <ul className="space-y-2">
          {lista.map((z) => (
            <li
              key={z.id}
              data-prueba={`zona-${z.nombre}`}
              className={`space-y-2 rounded-xl p-3 ring-1 ring-slate-200 ${z.activa ? 'bg-white' : 'bg-slate-50 text-slate-500'}`}
            >
              <p className="flex items-center gap-2 font-semibold">
                <span className="inline-block size-4 rounded-full" style={{ backgroundColor: z.color }} aria-hidden />
                {z.nombre}
                {!z.activa && <Insignia color="oscuro">Inactiva</Insignia>}
              </p>
              {modo.tipo === 'ver' && (
                <div className="flex flex-wrap gap-2">
                  <Boton variante="secundario" className="min-h-10 px-3 text-sm" onClick={() => setFormulario({ zona: z })}>
                    Nombre y color
                  </Boton>
                  <Boton
                    variante="secundario"
                    className="min-h-10 px-3 text-sm"
                    onClick={() => setModo({ tipo: 'forma', zona: z })}
                  >
                    Editar forma
                  </Boton>
                  <Boton
                    variante="secundario"
                    className="min-h-10 px-3 text-sm"
                    disabled={cambiarActiva.isPending}
                    onClick={() => cambiarActiva.mutate({ id: z.id, activa: !z.activa })}
                  >
                    {z.activa ? 'Desactivar' : 'Activar'}
                  </Boton>
                </div>
              )}
            </li>
          ))}
        </ul>
        <p className="text-sm text-slate-500">
          Si un punto cae en dos zonas que se enciman, cuenta la más pequeña. Una zona inactiva no se usa para
          calcular tarifas.
        </p>
      </aside>

      <Modal
        abierto={!!formulario}
        titulo={formulario?.zona ? 'Nombre y color de la zona' : 'Zona nueva'}
        onCerrar={() => setFormulario(null)}
      >
        {formulario && <FormularioZona {...formulario} onListo={() => setFormulario(null)} />}
      </Modal>
    </div>
  )
}

function Instrucciones({ modo }: { modo: Modo }) {
  const texto =
    modo.tipo === 'dibujar'
      ? 'Haz clic en el mapa para marcar cada esquina de la zona. Para cerrarla, haz clic otra vez en el primer punto.'
      : modo.tipo === 'forma'
        ? 'Arrastra los puntos para cambiar la forma. Arrastra los puntos intermedios para agregar esquinas.'
        : 'Usa «Satélite» (arriba a la derecha) para ver casas y calles.'
  return <p className={modo.tipo === 'ver' ? 'text-slate-600' : 'font-semibold text-amber-900'}>{texto}</p>
}

// Al cargar, encuadra todas las zonas.
function AjustarVista({ zonas }: { zonas: Zona[] }) {
  const map = useMap()
  const ajustado = useRef(false)
  useEffect(() => {
    if (ajustado.current || zonas.length === 0) return
    ajustado.current = true
    map.fitBounds(L.geoJSON(zonas.map((z) => z.poligono)).getBounds(), { padding: [20, 20] })
  }, [map, zonas])
  return null
}

function Dibujo({ activo, onTerminado }: { activo: boolean; onTerminado: (forma: Polygon) => void }) {
  const map = useMap()
  const alTerminar = useRef(onTerminado)
  useEffect(() => {
    alTerminar.current = onTerminado
  }, [onTerminado])

  useEffect(() => {
    if (!activo) return
    map.pm.setLang('es')
    map.pm.enableDraw('Polygon', { snappable: true, allowSelfIntersection: false })
    const alCrear = (e: { layer: L.Layer }) => {
      const forma = (e.layer as L.Polygon).toGeoJSON().geometry as Polygon
      map.removeLayer(e.layer)
      alTerminar.current(forma)
    }
    map.on('pm:create', alCrear)
    return () => {
      map.off('pm:create', alCrear)
      map.pm.disableDraw()
    }
  }, [activo, map])

  return null
}

// Capa editable con Geoman; se la entrega al padre para que lea la forma al guardar.
function EdicionForma({ zona, onCapa }: { zona: Zona; onCapa: (capa: CapaGeoJSON | null) => void }) {
  const map = useMap()
  useEffect(() => {
    const editable = L.geoJSON(zona.poligono, { style: { color: zona.color, weight: 3 } }).addTo(map)
    editable.eachLayer((l) => (l as L.Polygon).pm.enable({ allowSelfIntersection: false }))
    onCapa(editable)
    map.fitBounds(editable.getBounds(), { padding: [40, 40] })
    return () => {
      editable.remove()
      onCapa(null)
    }
    // onCapa cambia en cada render del padre; solo importa la zona.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [zona, map])
  return null
}

function FormularioZona({ zona, forma, onListo }: Formulario & { onListo: () => void }) {
  const guardar = useGuardarZona()
  const [nombre, setNombre] = useState(zona?.nombre ?? '')
  const [color, setColor] = useState(zona?.color ?? COLORES[0])

  function enviar(e: FormEvent) {
    e.preventDefault()
    const geometria = forma ?? zona?.poligono
    if (!geometria) return
    guardar.mutate({ id: zona?.id, nombre: nombre.trim(), color, forma: geometria }, { onSuccess: onListo })
  }

  return (
    <form onSubmit={enviar} className="space-y-4">
      <Campo etiqueta="Nombre de la zona" required value={nombre} onChange={(e) => setNombre(e.target.value)} autoFocus />
      <fieldset>
        <legend className="font-medium">Color</legend>
        <div className="mt-2 flex flex-wrap gap-2">
          {COLORES.map((c) => (
            <button
              key={c}
              type="button"
              aria-label={`Color ${c}`}
              aria-pressed={color === c}
              onClick={() => setColor(c)}
              className={`size-10 rounded-full ring-offset-2 ${color === c ? 'ring-4 ring-slate-900' : ''}`}
              style={{ backgroundColor: c }}
            />
          ))}
        </div>
      </fieldset>
      <MensajeError>{guardar.error && mensajeDeError(guardar.error)}</MensajeError>
      <div className="flex flex-wrap justify-end gap-3">
        <Boton type="button" variante="secundario" onClick={onListo}>
          Cancelar
        </Boton>
        <Boton type="submit" disabled={guardar.isPending}>
          {guardar.isPending ? 'Guardando…' : 'Guardar zona'}
        </Boton>
      </div>
    </form>
  )
}
