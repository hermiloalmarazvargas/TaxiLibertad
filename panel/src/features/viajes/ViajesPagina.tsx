import { useEffect, useState } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Modal } from '../../componentes/Modal'
import { mensajeDeError } from '../../lib/errores'
import { useAhora } from '../../lib/useAhora'
import { tieneSenal, useDespachoEnVivo, useTaxis, useViajesActivos, type Punto, type Viaje } from './api'
import { AsignarTaxi, CancelarViaje } from './Dialogos'
import { FormularioViajeTelefonico } from './FormularioViajeTelefonico'
import { MapaViajes, type ModoMarcar } from './MapaViajes'
import { TarjetaViaje } from './TarjetaViaje'

type Dialogo = { tipo: 'asignar' | 'cancelar'; viaje: Viaje }

export function ViajesPagina() {
  const conectado = useDespachoEnVivo()
  const viajes = useViajesActivos()
  const taxis = useTaxis()
  const ahora = useAhora(1_000)

  const [seleccionado, setSeleccionado] = useState<string | null>(null)
  const [dialogo, setDialogo] = useState<Dialogo | null>(null)
  // Formulario de viaje telefónico
  const [capturando, setCapturando] = useState(false)
  const [modoMarcar, setModoMarcar] = useState<ModoMarcar>(null)
  const [origen, setOrigen] = useState<Punto | null>(null)
  const [destino, setDestino] = useState<Punto | null>(null)

  const lista = viajes.data ?? []
  const listaTaxis = taxis.data ?? []
  const sinConductor = lista.filter((v) => v.estado === 'sin_conductor')
  const enCurso = lista.filter((v) => v.estado !== 'sin_conductor')
  const disponibles = listaTaxis.filter((t) => t.estado === 'disponible' && tieneSenal(t, ahora)).length
  const ocupados = listaTaxis.filter((t) => t.estado === 'ocupado').length

  // Aviso en la pestaña del navegador si hay viajes sin conductor.
  useEffect(() => {
    document.title = sinConductor.length
      ? `(${sinConductor.length}) ¡Sin conductor! · Despacho`
      : 'Despacho · Taxi Miahuatlán'
    return () => {
      document.title = 'Despacho · Taxi Miahuatlán'
    }
  }, [sinConductor.length])

  function abrirCaptura() {
    setCapturando(true)
    setOrigen(null)
    setDestino(null)
    setModoMarcar('origen')
  }

  function cerrarCaptura() {
    setCapturando(false)
    setModoMarcar(null)
    setOrigen(null)
    setDestino(null)
  }

  function marcar(punto: Punto) {
    if (modoMarcar === 'origen') setOrigen(punto)
    if (modoMarcar === 'destino') setDestino(punto)
    setModoMarcar(null)
  }

  const tarjeta = (v: Viaje) => (
    <TarjetaViaje
      key={v.id}
      viaje={v}
      taxis={listaTaxis}
      ahora={ahora}
      seleccionado={v.id === seleccionado}
      onSeleccionar={() => setSeleccionado(v.id)}
      onAsignar={() => setDialogo({ tipo: 'asignar', viaje: v })}
      onCancelar={() => setDialogo({ tipo: 'cancelar', viaje: v })}
    />
  )

  return (
    <section className="grid gap-4 xl:grid-cols-[1fr_26rem]">
      <div className="space-y-3">
        <header className="flex flex-wrap items-center justify-between gap-3">
          <h1 className="text-2xl font-bold">Viajes</h1>
          <div className="flex flex-wrap items-center gap-4 text-sm">
            <span data-prueba="taxis-disponibles">
              <span className="mr-1 inline-block size-3 rounded-full bg-green-600" aria-hidden />
              {disponibles} {disponibles === 1 ? 'disponible' : 'disponibles'}
            </span>
            <span>
              <span className="mr-1 inline-block size-3 rounded-full bg-amber-600" aria-hidden />
              {ocupados} {ocupados === 1 ? 'ocupado' : 'ocupados'}
            </span>
            <span
              data-prueba="conexion"
              className={`rounded-full px-3 py-1 font-semibold ${conectado ? 'bg-green-100 text-green-900' : 'bg-red-100 text-red-900'}`}
            >
              {conectado ? '● En vivo' : '● Reconectando…'}
            </span>
          </div>
        </header>
        <MapaViajes
          viajes={lista}
          taxis={listaTaxis}
          ahora={ahora}
          seleccionado={seleccionado}
          onSeleccionar={setSeleccionado}
          modoMarcar={modoMarcar}
          origen={origen}
          destino={destino}
          onMarcar={marcar}
        />
      </div>

      <aside className="space-y-4">
        {capturando ? (
          <div className="rounded-xl bg-white p-4 ring-1 ring-slate-200">
            <FormularioViajeTelefonico
              taxis={listaTaxis}
              ahora={ahora}
              origen={origen}
              destino={destino}
              modoMarcar={modoMarcar}
              onModoMarcar={setModoMarcar}
              onQuitarDestino={() => setDestino(null)}
              onCreado={(id) => {
                cerrarCaptura()
                setSeleccionado(id)
              }}
              onCancelar={cerrarCaptura}
            />
          </div>
        ) : (
          <Boton className="w-full" onClick={abrirCaptura}>
            Nuevo viaje por teléfono
          </Boton>
        )}

        <MensajeError>{viajes.error && mensajeDeError(viajes.error)}</MensajeError>

        {sinConductor.length > 0 && (
          <div className="space-y-2" role="alert">
            <h2 className="font-bold text-red-800">⚠ Sin conductor ({sinConductor.length})</h2>
            <p className="text-sm text-red-800">Nadie aceptó. Asigna un taxi o llama al pasajero.</p>
            <ul className="space-y-2">{sinConductor.map(tarjeta)}</ul>
          </div>
        )}

        <div className="space-y-2">
          <h2 className="font-bold">Viajes activos ({enCurso.length})</h2>
          {viajes.isPending ? (
            <p className="text-slate-500">Cargando…</p>
          ) : enCurso.length === 0 ? (
            <p className="text-slate-500">No hay viajes en curso.</p>
          ) : (
            <ul className="space-y-2" data-prueba="viajes-activos">
              {enCurso.map(tarjeta)}
            </ul>
          )}
        </div>
      </aside>

      <Modal abierto={dialogo?.tipo === 'asignar'} titulo="Asignar taxi" onCerrar={() => setDialogo(null)}>
        {dialogo?.tipo === 'asignar' && (
          <AsignarTaxi viaje={dialogo.viaje} taxis={listaTaxis} ahora={ahora} onListo={() => setDialogo(null)} />
        )}
      </Modal>
      <Modal abierto={dialogo?.tipo === 'cancelar'} titulo="Cancelar viaje" onCerrar={() => setDialogo(null)}>
        {dialogo?.tipo === 'cancelar' && <CancelarViaje viaje={dialogo.viaje} onListo={() => setDialogo(null)} />}
      </Modal>
    </section>
  )
}
