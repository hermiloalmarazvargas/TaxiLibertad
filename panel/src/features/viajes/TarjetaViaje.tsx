import { Insignia } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { formatoTelefono } from '../../lib/formato'
import { hace } from '../../lib/distancia'
import { contactoDe, type Taxi, type Viaje } from './api'
import { ESTADO } from './estados'

const pesos = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' })

type Props = {
  viaje: Viaje
  taxis: Taxi[]
  ahora: number
  seleccionado: boolean
  onSeleccionar: () => void
  onAsignar: () => void
  onCancelar: () => void
}

export function TarjetaViaje({ viaje: v, taxis, ahora, seleccionado, onSeleccionar, onAsignar, onCancelar }: Props) {
  const contacto = contactoDe(v)
  const oferta = v.ofertas.find((o) => o.respuesta === 'pendiente')
  const ofrecidoA = oferta && taxis.find((t) => t.conductor_id === oferta.conductor_id)
  const segundos = oferta ? Math.max(0, Math.ceil((new Date(oferta.expira_en).getTime() - ahora) / 1000)) : 0
  const asignable = v.estado === 'buscando' || v.estado === 'sin_conductor'

  return (
    <li
      data-prueba={`viaje-${v.id}`}
      className={`space-y-2 rounded-xl bg-white p-3 ring-1 ${
        v.estado === 'sin_conductor' ? 'ring-2 ring-red-500' : seleccionado ? 'ring-2 ring-slate-900' : 'ring-slate-200'
      }`}
    >
      <button type="button" onClick={onSeleccionar} className="block w-full space-y-1 text-left">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Insignia color={ESTADO[v.estado].insignia}>{ESTADO[v.estado].texto}</Insignia>
          <span className="text-sm text-slate-500">{hace(v.solicitado_en, ahora)}</span>
        </div>
        <p className="font-semibold">
          {v.canal === 'telefono' ? '📞 ' : '📱 '}
          {contacto.nombre}
          {contacto.telefono && <span className="font-normal text-slate-600"> · {formatoTelefono(contacto.telefono)}</span>}
        </p>
        <p>
          <span className="text-slate-500">De: </span>
          {v.origen_referencia || <span className="text-slate-400">sin referencia</span>}
          {v.zona_origen && <span className="text-slate-500"> ({v.zona_origen.nombre})</span>}
        </p>
        {(v.destino_referencia || v.zona_destino) && (
          <p>
            <span className="text-slate-500">A: </span>
            {v.destino_referencia || <span className="text-slate-400">sin referencia</span>}
            {v.zona_destino && <span className="text-slate-500"> ({v.zona_destino.nombre})</span>}
          </p>
        )}
        <p className="text-sm">
          {v.tarifa_monto == null ? (
            'Tarifa a convenir'
          ) : (
            <>
              Tarifa {pesos.format(Number(v.tarifa_monto))}
              {Number(v.tarifa_recargo) > 0 && (
                <span className="text-slate-500"> (incluye {pesos.format(Number(v.tarifa_recargo))} nocturno)</span>
              )}
            </>
          )}
        </p>
        {v.conductor?.perfil && (
          <p className="text-sm font-semibold">
            🚕 {v.conductor.perfil.nombre}
            {v.unidad && ` · Unidad ${v.unidad.numero_economico}`}
          </p>
        )}
        {v.estado === 'buscando' && (
          <p className="text-sm text-amber-900" data-prueba="oferta">
            {ofrecidoA
              ? `Ofrecido a ${ofrecidoA.conductor?.perfil?.nombre ?? 'un conductor'} · ${segundos} s`
              : 'Esperando un taxi disponible…'}
          </p>
        )}
      </button>

      <div className="flex flex-wrap gap-2">
        {asignable && (
          <Boton className="min-h-10 px-3 text-sm" onClick={onAsignar}>
            Asignar taxi
          </Boton>
        )}
        <Boton variante="secundario" className="min-h-10 px-3 text-sm" onClick={onCancelar}>
          Cancelar viaje
        </Boton>
      </div>
    </li>
  )
}
