import { useState, type FormEvent } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo } from '../../componentes/Campo'
import { mensajeDeError } from '../../lib/errores'
import { recargoDe, useGuardarRecargo, useRecargo, type Recargo } from './api'

const pesos = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN', maximumFractionDigits: 2 })
const TARIFA_EJEMPLO = 45

export function RecargoNocturno() {
  const recargo = useRecargo()
  // La mutación vive aquí: el formulario se vuelve a crear al guardar y
  // perdería el aviso de "guardado".
  const guardar = useGuardarRecargo()
  if (recargo.isPending) return null
  if (recargo.error) return <MensajeError>{mensajeDeError(recargo.error)}</MensajeError>
  // La clave reinicia el formulario cuando cambia lo guardado.
  return <FormularioRecargo key={JSON.stringify(recargo.data)} guardado={recargo.data} guardar={guardar} />
}

function FormularioRecargo({ guardado, guardar }: { guardado: Recargo; guardar: ReturnType<typeof useGuardarRecargo> }) {
  const [porcentaje, setPorcentaje] = useState(String(guardado.porcentaje))
  const [desde, setDesde] = useState(guardado.desde)
  const [hasta, setHasta] = useState(guardado.hasta)

  const pct = Number(porcentaje)
  const valido = porcentaje.trim() !== '' && Number.isFinite(pct) && pct >= 0 && pct <= 100
  const cambiado = pct !== guardado.porcentaje || desde !== guardado.desde || hasta !== guardado.hasta
  const extra = valido ? recargoDe(TARIFA_EJEMPLO, pct) : 0

  function enviar(e: FormEvent) {
    e.preventDefault()
    if (valido) guardar.mutate({ porcentaje: pct, desde, hasta })
  }

  return (
    <form
      onSubmit={enviar}
      className="max-w-3xl space-y-4 rounded-xl bg-white p-4 ring-1 ring-slate-200"
      aria-labelledby="titulo-recargo"
    >
      <h2 id="titulo-recargo" className="text-lg font-semibold">
        Recargo nocturno
      </h2>
      <div className="grid gap-4 sm:grid-cols-3">
        <Campo
          etiqueta="Porcentaje"
          type="number"
          min={0}
          max={100}
          step={1}
          inputMode="numeric"
          required
          value={porcentaje}
          onChange={(e) => setPorcentaje(e.target.value)}
          ayuda="0 = sin recargo"
        />
        <Campo etiqueta="Desde" type="time" required value={desde} onChange={(e) => setDesde(e.target.value)} />
        <Campo etiqueta="Hasta" type="time" required value={hasta} onChange={(e) => setHasta(e.target.value)} />
      </div>

      <p className="text-slate-700" data-prueba="ejemplo-recargo">
        {!valido
          ? 'El porcentaje debe estar entre 0 y 100.'
          : pct === 0
            ? 'Sin recargo nocturno.'
            : `Ejemplo: un viaje de ${pesos.format(TARIFA_EJEMPLO)} pedido entre las ${desde} y las ${hasta} cuesta ${pesos.format(TARIFA_EJEMPLO + extra)} (+${pesos.format(extra)}).`}
      </p>
      <p className="text-sm text-slate-500">
        Cuenta la hora en que se pide el viaje. El recargo se redondea al peso. Los viajes «a convenir» siguen a
        convenir.
      </p>

      <MensajeError>{guardar.error && mensajeDeError(guardar.error)}</MensajeError>
      <div className="flex flex-wrap items-center gap-3">
        <Boton type="submit" disabled={!valido || !cambiado || guardar.isPending}>
          {guardar.isPending ? 'Guardando…' : 'Guardar recargo'}
        </Boton>
        {guardar.isSuccess && !cambiado && <p className="text-green-800">Recargo guardado ✓</p>}
      </div>
    </form>
  )
}
