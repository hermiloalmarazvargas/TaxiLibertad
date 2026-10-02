import { useState } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { mensajeDeError } from '../../lib/errores'
import { claveTarifa, useGuardarTarifas, useTarifas, useZonas, type CambioTarifa } from './api'

// Texto capturado por celda que aún no se guarda. "" = quitar ("a convenir").
type Pendientes = Map<string, string>

const MONTO_VALIDO = /^\d{1,4}(\.\d{1,2})?$/

export function TablaTarifas() {
  const zonas = useZonas()
  const tarifas = useTarifas()
  const guardar = useGuardarTarifas()
  const [pendientes, setPendientes] = useState<Pendientes>(new Map())
  const [mismoRegreso, setMismoRegreso] = useState(true)
  const [aviso, setAviso] = useState<string | null>(null)

  const activas = (zonas.data ?? []).filter((z) => z.activa)
  const guardadas = tarifas.data ?? new Map<string, number>()

  const valorGuardado = (clave: string) => (guardadas.has(clave) ? String(guardadas.get(clave)) : '')
  const valor = (clave: string) => pendientes.get(clave) ?? valorGuardado(clave)

  function cambiar(origen: number, destino: number, texto: string) {
    setAviso(null)
    const siguiente = new Map(pendientes)
    const claves = [claveTarifa(origen, destino)]
    if (mismoRegreso && origen !== destino) claves.push(claveTarifa(destino, origen))
    for (const clave of claves) {
      // Si vuelve al valor guardado, deja de estar pendiente.
      if (texto === valorGuardado(clave)) siguiente.delete(clave)
      else siguiente.set(clave, texto)
    }
    setPendientes(siguiente)
  }

  function guardarCambios() {
    const invalidos = [...pendientes.values()].filter((t) => t.trim() !== '' && !MONTO_VALIDO.test(t.trim()))
    if (invalidos.length) {
      setAviso('Revisa los montos: solo números, por ejemplo 35 o 42.50')
      return
    }
    const cambios: CambioTarifa[] = [...pendientes.entries()].map(([clave, texto]) => {
      const [origen, destino] = clave.split('-').map(Number)
      return { origen, destino, monto: texto.trim() === '' ? null : Number(texto) }
    })
    if (cambios.some((c) => c.monto === 0)) {
      setAviso('Una tarifa no puede ser 0. Déjala vacía si es «a convenir».')
      return
    }
    guardar.mutate(cambios, { onSuccess: () => setPendientes(new Map()) })
  }

  if (zonas.isPending || tarifas.isPending) return <p className="text-slate-500">Cargando…</p>
  if (activas.length === 0) return <p className="text-slate-500">Primero dibuja al menos una zona.</p>

  return (
    <div className="space-y-4">
      <p className="max-w-prose text-slate-600">
        Precio por viaje de la zona de la izquierda (origen) a la zona de arriba (destino). Una casilla vacía significa
        tarifa <strong>a convenir</strong>.
      </p>

      <label className="flex min-h-12 items-center gap-2">
        <input
          type="checkbox"
          className="size-5"
          checked={mismoRegreso}
          onChange={(e) => setMismoRegreso(e.target.checked)}
        />
        Aplicar el mismo precio de regreso (A→B también para B→A)
      </label>

      <div className="overflow-x-auto rounded-xl bg-white ring-1 ring-slate-200">
        <table className="text-left" data-prueba="tabla-tarifas">
          <thead>
            <tr className="border-b border-slate-200 text-sm text-slate-600">
              <th className="sticky left-0 bg-white p-3 font-semibold">Origen ↓ / Destino →</th>
              {activas.map((d) => (
                <th key={d.id} className="p-3 font-semibold whitespace-nowrap">
                  {d.nombre}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {activas.map((o) => (
              <tr key={o.id} className="border-b border-slate-100 last:border-0">
                <th className="sticky left-0 bg-white p-3 font-semibold whitespace-nowrap">{o.nombre}</th>
                {activas.map((d) => {
                  const clave = claveTarifa(o.id, d.id)
                  const cambiado = pendientes.has(clave)
                  return (
                    <td key={d.id} className="p-2">
                      <div className="relative">
                        <span className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-slate-500">$</span>
                        <input
                          aria-label={`Tarifa de ${o.nombre} a ${d.nombre}`}
                          inputMode="decimal"
                          placeholder="a convenir"
                          value={valor(clave)}
                          onChange={(e) => cambiar(o.id, d.id, e.target.value)}
                          className={`min-h-12 w-32 rounded-lg border pr-2 pl-7 text-right text-lg tabular-nums ${
                            cambiado ? 'border-amber-500 bg-amber-50' : 'border-slate-300'
                          }`}
                        />
                      </div>
                    </td>
                  )
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <MensajeError>{aviso ?? (guardar.error && mensajeDeError(guardar.error))}</MensajeError>

      <div className="flex flex-wrap items-center gap-3">
        <Boton onClick={guardarCambios} disabled={pendientes.size === 0 || guardar.isPending}>
          {guardar.isPending ? 'Guardando…' : `Guardar cambios${pendientes.size ? ` (${pendientes.size})` : ''}`}
        </Boton>
        <Boton
          variante="secundario"
          disabled={pendientes.size === 0}
          onClick={() => {
            setPendientes(new Map())
            setAviso(null)
          }}
        >
          Descartar
        </Boton>
        {guardar.isSuccess && pendientes.size === 0 && <p className="text-green-800">Tarifas guardadas ✓</p>}
      </div>
    </div>
  )
}
