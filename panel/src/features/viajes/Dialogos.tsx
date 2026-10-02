import { useState } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo } from '../../componentes/Campo'
import { formatoDistancia } from '../../lib/distancia'
import { mensajeDeError } from '../../lib/errores'
import { formatoTelefono } from '../../lib/formato'
import { useBloquear } from '../bloqueos/api'
import { contactoDe, useAsignarViaje, useCancelarViaje, type Taxi, type Viaje } from './api'
import { taxisCercanos } from './cercanos'

export function AsignarTaxi({ viaje, taxis, ahora, onListo }: { viaje: Viaje; taxis: Taxi[]; ahora: number; onListo: () => void }) {
  const asignar = useAsignarViaje()
  const opciones = taxisCercanos(taxis, { lat: viaje.origen_lat!, lng: viaje.origen_lng! }, ahora)

  return (
    <div className="space-y-4">
      <p>
        El viaje queda asignado de inmediato y se avisa al conductor. Origen:{' '}
        <strong>{viaje.origen_referencia || 'sin referencia'}</strong>
      </p>
      {opciones.length === 0 ? (
        <p className="rounded-lg bg-slate-50 p-3 text-slate-600">No hay taxis disponibles en este momento.</p>
      ) : (
        <ul className="max-h-80 space-y-2 overflow-y-auto">
          {opciones.map(({ taxi, senal, metros }) => (
            <li key={taxi.conductor_id} className="flex items-center justify-between gap-3 rounded-lg p-2 ring-1 ring-slate-200">
              <div>
                <p className="font-semibold">
                  Unidad {taxi.unidad?.numero_economico} · {taxi.conductor?.perfil?.nombre}
                </p>
                <p className="text-sm text-slate-600">
                  {metros != null ? `A ${formatoDistancia(metros)} en línea recta` : 'Sin ubicación'}
                  {!senal && ' · sin señal reciente'}
                </p>
              </div>
              <Boton
                className="min-h-10 px-3 text-sm"
                disabled={asignar.isPending}
                onClick={() => asignar.mutate({ viajeId: viaje.id, conductorId: taxi.conductor_id }, { onSuccess: onListo })}
              >
                Asignar
              </Boton>
            </li>
          ))}
        </ul>
      )}
      <MensajeError>{asignar.error && mensajeDeError(asignar.error)}</MensajeError>
      <div className="flex justify-end">
        <Boton variante="secundario" onClick={onListo}>
          Cerrar
        </Boton>
      </div>
    </div>
  )
}

const MOTIVOS = ['El pasajero ya no lo necesita', 'No se encontró al pasajero', 'Llamada falsa']

export function CancelarViaje({ viaje, onListo }: { viaje: Viaje; onListo: () => void }) {
  const cancelar = useCancelarViaje()
  const bloquear = useBloquear()
  const [motivo, setMotivo] = useState('')
  const [bloquearNumero, setBloquearNumero] = useState(false)
  const contacto = contactoDe(viaje)

  async function confirmar() {
    await cancelar.mutateAsync({ viajeId: viaje.id, motivo })
    if (bloquearNumero && contacto.telefono) {
      // Si ya estaba bloqueado no pasa nada: el viaje igual quedó cancelado.
      await bloquear.mutateAsync({ telefono: contacto.telefono, motivo: motivo || 'Llamada falsa' }).catch(() => {})
    }
    onListo()
  }

  return (
    <div className="space-y-4">
      <p>
        Viaje de <strong>{contacto.nombre}</strong>
        {viaje.estado === 'en_curso' && ' — ya va a bordo; avisa al conductor.'}
      </p>
      <Campo etiqueta="Motivo (opcional)" list="motivos-cancelacion" value={motivo} onChange={(e) => setMotivo(e.target.value)} />
      <datalist id="motivos-cancelacion">
        {MOTIVOS.map((m) => (
          <option key={m} value={m} />
        ))}
      </datalist>
      {contacto.telefono && (
        <label className="flex min-h-12 items-center gap-2">
          <input type="checkbox" className="size-5" checked={bloquearNumero} onChange={(e) => setBloquearNumero(e.target.checked)} />
          Bloquear el número {formatoTelefono(contacto.telefono)} (pedidos falsos)
        </label>
      )}
      <MensajeError>{cancelar.error && mensajeDeError(cancelar.error)}</MensajeError>
      <div className="flex flex-wrap justify-end gap-3">
        <Boton variante="secundario" onClick={onListo}>
          Volver
        </Boton>
        <Boton variante="peligro" disabled={cancelar.isPending} onClick={() => void confirmar().catch(() => {})}>
          Cancelar viaje
        </Boton>
      </div>
    </div>
  )
}
