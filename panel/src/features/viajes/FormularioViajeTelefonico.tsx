import { useState, type FormEvent } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo, Selector } from '../../componentes/Campo'
import { formatoDistancia } from '../../lib/distancia'
import { mensajeDeError } from '../../lib/errores'
import { normalizarTelefono } from '../../lib/formato'
import { useCrearViajeTelefonico, useTarifaEstimada, type Punto, type Taxi } from './api'
import { taxisCercanos } from './cercanos'
import type { ModoMarcar } from './MapaViajes'

const pesos = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' })

type Props = {
  taxis: Taxi[]
  ahora: number
  origen: Punto | null
  destino: Punto | null
  modoMarcar: ModoMarcar
  onModoMarcar: (modo: ModoMarcar) => void
  onQuitarDestino: () => void
  onCreado: (viajeId: string) => void
  onCancelar: () => void
}

export function FormularioViajeTelefonico(props: Props) {
  const { taxis, ahora, origen, destino, modoMarcar, onModoMarcar, onQuitarDestino, onCreado, onCancelar } = props
  const crear = useCrearViajeTelefonico()
  const tarifa = useTarifaEstimada(origen, destino)
  // Un id por formulario: si se pulsa dos veces o se reintenta sin señal, el
  // servidor reconoce la solicitud y no crea un viaje duplicado.
  const [clientRequestId] = useState(() => crypto.randomUUID())
  const [nombre, setNombre] = useState('')
  const [telefono, setTelefono] = useState('')
  const [origenReferencia, setOrigenReferencia] = useState('')
  const [destinoReferencia, setDestinoReferencia] = useState('')
  const [conductorId, setConductorId] = useState('')
  const [aviso, setAviso] = useState<string | null>(null)

  const cercanos = origen ? taxisCercanos(taxis, origen, ahora) : []

  function enviar(e: FormEvent) {
    e.preventDefault()
    if (!origen) {
      setAviso('Marca en el mapa dónde recoger al pasajero')
      return
    }
    if (!normalizarTelefono(telefono)) {
      setAviso('El teléfono debe tener 10 dígitos')
      return
    }
    setAviso(null)
    crear.mutate(
      {
        clientRequestId,
        nombre: nombre.trim(),
        telefono,
        origen,
        origenReferencia: origenReferencia.trim(),
        destino,
        destinoReferencia: destinoReferencia.trim(),
        conductorId: conductorId || null,
      },
      { onSuccess: (viaje) => onCreado(viaje.id) },
    )
  }

  const botonMarcar = (modo: 'origen' | 'destino', punto: Punto | null, texto: string) => (
    <Boton
      type="button"
      variante={modoMarcar === modo ? 'primario' : 'secundario'}
      className="min-h-10 px-3 text-sm"
      aria-pressed={modoMarcar === modo}
      onClick={() => onModoMarcar(modoMarcar === modo ? null : modo)}
    >
      {modoMarcar === modo ? 'Haz clic en el mapa…' : punto ? `Cambiar ${texto}` : `Marcar ${texto}`}
    </Boton>
  )

  return (
    <form onSubmit={enviar} className="space-y-4">
      <h2 className="text-xl font-bold">Nuevo viaje por teléfono</h2>

      <div className="grid gap-3 sm:grid-cols-2">
        <Campo etiqueta="Nombre" required value={nombre} onChange={(e) => setNombre(e.target.value)} autoFocus />
        <Campo etiqueta="Teléfono" type="tel" inputMode="tel" required value={telefono} onChange={(e) => setTelefono(e.target.value)} />
      </div>

      <fieldset className="space-y-2 rounded-xl p-3 ring-1 ring-slate-200">
        <legend className="px-1 font-semibold">¿Dónde lo recogemos?</legend>
        <div className="flex flex-wrap items-center gap-2">
          {botonMarcar('origen', origen, 'origen')}
          {origen && <span className="text-sm text-green-800">✓ Marcado</span>}
        </div>
        <Campo
          etiqueta="Referencia"
          placeholder="Ej.: frente a la iglesia, portón verde"
          value={origenReferencia}
          onChange={(e) => setOrigenReferencia(e.target.value)}
        />
      </fieldset>

      <fieldset className="space-y-2 rounded-xl p-3 ring-1 ring-slate-200">
        <legend className="px-1 font-semibold">¿A dónde va? (opcional)</legend>
        <div className="flex flex-wrap items-center gap-2">
          {botonMarcar('destino', destino, 'destino')}
          {destino && (
            <Boton type="button" variante="secundario" className="min-h-10 px-3 text-sm" onClick={onQuitarDestino}>
              Quitar destino
            </Boton>
          )}
        </div>
        <Campo etiqueta="Referencia del destino" value={destinoReferencia} onChange={(e) => setDestinoReferencia(e.target.value)} />
      </fieldset>

      {origen && (
        <p className="rounded-lg bg-slate-50 p-3 text-lg" data-prueba="tarifa-estimada">
          {tarifa.isPending
            ? 'Calculando tarifa…'
            : tarifa.data?.monto == null
              ? `Tarifa a convenir${tarifa.data?.nocturno ? ' (horario nocturno)' : ''}`
              : `Tarifa: ${pesos.format(Number(tarifa.data.monto))}${
                  Number(tarifa.data.recargo) > 0 ? ` (incluye ${pesos.format(Number(tarifa.data.recargo))} de recargo nocturno)` : ''
                }`}
        </p>
      )}

      <Selector etiqueta="Taxi" value={conductorId} onChange={(e) => setConductorId(e.target.value)}>
        <option value="">Asignación automática (el más cercano que acepte)</option>
        {cercanos.map(({ taxi, metros, senal }) => (
          <option key={taxi.conductor_id} value={taxi.conductor_id}>
            Unidad {taxi.unidad?.numero_economico} · {taxi.conductor?.perfil?.nombre}
            {metros != null ? ` · ${formatoDistancia(metros)}` : ''}
            {!senal ? ' · sin señal' : ''}
          </option>
        ))}
      </Selector>

      <MensajeError>{aviso ?? (crear.error && mensajeDeError(crear.error))}</MensajeError>

      <div className="flex flex-wrap justify-end gap-3">
        <Boton type="button" variante="secundario" onClick={onCancelar}>
          Cancelar
        </Boton>
        <Boton type="submit" disabled={crear.isPending}>
          {crear.isPending ? 'Creando…' : 'Crear viaje'}
        </Boton>
      </div>
    </form>
  )
}
