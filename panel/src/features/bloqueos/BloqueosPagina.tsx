import { useState, type FormEvent } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo } from '../../componentes/Campo'
import { Modal } from '../../componentes/Modal'
import { mensajeDeError } from '../../lib/errores'
import { formatoHora, formatoTelefono, normalizarTelefono } from '../../lib/formato'
import { useBloquear, useBloqueos, useDesbloquear, type Bloqueo } from './api'

const MOTIVOS_FRECUENTES = ['Pedidos falsos', 'No se presentó varias veces', 'Agresión al conductor']

export function BloqueosPagina() {
  const bloqueos = useBloqueos()
  const [busqueda, setBusqueda] = useState('')
  const [porDesbloquear, setPorDesbloquear] = useState<Bloqueo | null>(null)

  const digitos = busqueda.replace(/\D/g, '')
  const visibles = (bloqueos.data ?? []).filter((b) => !digitos || b.telefono.includes(digitos))

  return (
    <section className="space-y-6">
      <h1 className="text-2xl font-bold">Números bloqueados</h1>
      <p className="max-w-prose text-slate-600">
        Un número bloqueado no puede pedir viajes desde la app ni registrarse de nuevo, y el despacho no puede
        crearle viajes por teléfono.
      </p>

      <FormularioBloqueo />

      <div className="space-y-4">
        <input
          type="search"
          inputMode="tel"
          placeholder="Buscar número"
          aria-label="Buscar número bloqueado"
          className="block min-h-12 w-full max-w-xs rounded-lg border border-slate-300 bg-white px-3 text-lg"
          value={busqueda}
          onChange={(e) => setBusqueda(e.target.value)}
        />

        <MensajeError>{bloqueos.error && mensajeDeError(bloqueos.error)}</MensajeError>

        {bloqueos.isPending ? (
          <p className="text-slate-500">Cargando…</p>
        ) : visibles.length === 0 ? (
          <p className="text-slate-500">{digitos ? 'Ese número no está bloqueado.' : 'No hay números bloqueados.'}</p>
        ) : (
          <ul className="divide-y divide-slate-100 rounded-xl bg-white ring-1 ring-slate-200">
            {visibles.map((b) => (
              <li
                key={b.telefono}
                data-prueba={`bloqueo-${b.telefono}`}
                className="flex flex-wrap items-center justify-between gap-3 p-4"
              >
                <div>
                  <p className="font-mono text-lg font-semibold">{formatoTelefono(b.telefono)}</p>
                  {b.pasajero && <p className="text-sm">Pasajero registrado: {b.pasajero}</p>}
                  <p className="text-sm text-slate-600">
                    {b.motivo} · {formatoHora(b.bloqueado_en)}
                    {b.quien?.nombre && ` · por ${b.quien.nombre}`}
                  </p>
                </div>
                <Boton variante="secundario" onClick={() => setPorDesbloquear(b)}>
                  Desbloquear
                </Boton>
              </li>
            ))}
          </ul>
        )}
      </div>

      <Modal abierto={!!porDesbloquear} titulo="Desbloquear número" onCerrar={() => setPorDesbloquear(null)}>
        {porDesbloquear && <ConfirmarDesbloqueo bloqueo={porDesbloquear} onListo={() => setPorDesbloquear(null)} />}
      </Modal>
    </section>
  )
}

function FormularioBloqueo() {
  const bloquear = useBloquear()
  const [telefono, setTelefono] = useState('')
  const [motivo, setMotivo] = useState('')
  const [errorTelefono, setErrorTelefono] = useState<string | null>(null)

  function enviar(e: FormEvent) {
    e.preventDefault()
    const normalizado = normalizarTelefono(telefono)
    if (!normalizado) {
      setErrorTelefono('El teléfono debe tener 10 dígitos')
      return
    }
    setErrorTelefono(null)
    bloquear.mutate(
      { telefono: normalizado, motivo: motivo.trim() },
      {
        onSuccess: () => {
          setTelefono('')
          setMotivo('')
        },
      },
    )
  }

  return (
    <form onSubmit={enviar} className="max-w-2xl space-y-4 rounded-xl bg-white p-4 ring-1 ring-slate-200">
      <h2 className="text-lg font-semibold">Bloquear un número</h2>
      <div className="grid gap-4 sm:grid-cols-2">
        <Campo
          etiqueta="Teléfono"
          type="tel"
          inputMode="tel"
          required
          value={telefono}
          onChange={(e) => setTelefono(e.target.value)}
          ayuda="10 dígitos"
        />
        <Campo
          etiqueta="Motivo"
          required
          list="motivos-bloqueo"
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
        />
        <datalist id="motivos-bloqueo">
          {MOTIVOS_FRECUENTES.map((m) => (
            <option key={m} value={m} />
          ))}
        </datalist>
      </div>
      <MensajeError>{errorTelefono ?? (bloquear.error && mensajeDeError(bloquear.error))}</MensajeError>
      <Boton type="submit" variante="peligro" disabled={bloquear.isPending}>
        {bloquear.isPending ? 'Bloqueando…' : 'Bloquear número'}
      </Boton>
    </form>
  )
}

function ConfirmarDesbloqueo({ bloqueo, onListo }: { bloqueo: Bloqueo; onListo: () => void }) {
  const desbloquear = useDesbloquear()
  return (
    <div className="space-y-4">
      <p>
        El número <strong>{formatoTelefono(bloqueo.telefono)}</strong> podrá volver a pedir viajes.
      </p>
      <MensajeError>{desbloquear.error && mensajeDeError(desbloquear.error)}</MensajeError>
      <div className="flex flex-wrap justify-end gap-3">
        <Boton variante="secundario" onClick={onListo}>
          Cancelar
        </Boton>
        <Boton disabled={desbloquear.isPending} onClick={() => desbloquear.mutate(bloqueo.telefono, { onSuccess: onListo })}>
          Desbloquear
        </Boton>
      </div>
    </div>
  )
}
