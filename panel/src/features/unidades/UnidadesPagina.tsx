import { useState } from 'react'
import { Insignia, MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Selector } from '../../componentes/Campo'
import { Modal } from '../../componentes/Modal'
import { mensajeDeError } from '../../lib/errores'
import { formatoTelefono } from '../../lib/formato'
import {
  conductorEnServicio,
  useGuardarSitio,
  useGuardarUnidad,
  useTodosLosSitios,
  useUnidades,
  type Sitio,
  type Unidad,
} from './api'
import { FormularioSitio } from './FormularioSitio'
import { FormularioUnidad } from './FormularioUnidad'

type Dialogo = { tipo: 'unidad'; unidad?: Unidad } | { tipo: 'sitio'; sitio?: Sitio }

export function UnidadesPagina() {
  const sitios = useTodosLosSitios()
  const unidades = useUnidades()
  const [dialogo, setDialogo] = useState<Dialogo | null>(null)
  const [filtroSitio, setFiltroSitio] = useState('')
  const [verInactivas, setVerInactivas] = useState(false)
  const cerrar = () => setDialogo(null)

  const visibles = (unidades.data ?? []).filter(
    (u) => (verInactivas || u.activo) && (!filtroSitio || String(u.sitio_id) === filtroSitio),
  )

  return (
    <section className="space-y-8">
      <SeccionSitios
        sitios={sitios.data ?? []}
        unidades={unidades.data}
        cargando={sitios.isPending}
        error={sitios.error}
        onAgregar={() => setDialogo({ tipo: 'sitio' })}
        onEditar={(sitio) => setDialogo({ tipo: 'sitio', sitio })}
      />

      <div className="space-y-4">
        <header className="flex flex-wrap items-center justify-between gap-4">
          <h1 className="text-2xl font-bold">Unidades</h1>
          <Boton onClick={() => setDialogo({ tipo: 'unidad' })} disabled={!sitios.data?.some((s) => s.activo)}>
            Agregar unidad
          </Boton>
        </header>

        <div className="flex flex-wrap items-end gap-4">
          <div className="w-full max-w-xs">
            <Selector etiqueta="Sitio" value={filtroSitio} onChange={(e) => setFiltroSitio(e.target.value)}>
              <option value="">Todos</option>
              {sitios.data?.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.nombre}
                </option>
              ))}
            </Selector>
          </div>
          <label className="flex min-h-12 items-center gap-2">
            <input
              type="checkbox"
              className="size-5"
              checked={verInactivas}
              onChange={(e) => setVerInactivas(e.target.checked)}
            />
            Mostrar inactivas
          </label>
        </div>

        <MensajeError>{unidades.error && mensajeDeError(unidades.error)}</MensajeError>

        {unidades.isPending ? (
          <p className="text-slate-500">Cargando…</p>
        ) : visibles.length === 0 ? (
          <p className="text-slate-500">No hay unidades.</p>
        ) : (
          <div className="overflow-x-auto rounded-xl bg-white ring-1 ring-slate-200">
            <table className="w-full min-w-[44rem] text-left">
              <thead className="border-b border-slate-200 text-sm text-slate-600">
                <tr>
                  <th className="p-3 font-semibold">Número</th>
                  <th className="p-3 font-semibold">Placas</th>
                  <th className="p-3 font-semibold">Vehículo</th>
                  <th className="p-3 font-semibold">Sitio</th>
                  <th className="p-3 font-semibold">Estado</th>
                  <th className="p-3 font-semibold">Acciones</th>
                </tr>
              </thead>
              <tbody>
                {visibles.map((u) => (
                  <FilaUnidad key={u.id} unidad={u} onEditar={() => setDialogo({ tipo: 'unidad', unidad: u })} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <Modal
        abierto={dialogo?.tipo === 'unidad'}
        titulo={dialogo?.tipo === 'unidad' && dialogo.unidad ? 'Editar unidad' : 'Agregar unidad'}
        onCerrar={cerrar}
      >
        {dialogo?.tipo === 'unidad' && (
          <FormularioUnidad unidad={dialogo.unidad} sitios={sitios.data ?? []} onListo={cerrar} />
        )}
      </Modal>

      <Modal
        abierto={dialogo?.tipo === 'sitio'}
        titulo={dialogo?.tipo === 'sitio' && dialogo.sitio ? 'Editar sitio' : 'Agregar sitio'}
        onCerrar={cerrar}
      >
        {dialogo?.tipo === 'sitio' && <FormularioSitio sitio={dialogo.sitio} onListo={cerrar} />}
      </Modal>
    </section>
  )
}

function FilaUnidad({ unidad, onEditar }: { unidad: Unidad; onEditar: () => void }) {
  const guardar = useGuardarUnidad()
  const conductor = conductorEnServicio(unidad)
  const vehiculo = [unidad.marca, unidad.modelo, unidad.color].filter(Boolean).join(' · ')

  return (
    <tr
      data-prueba={`unidad-${unidad.placas}`}
      className={`border-b border-slate-100 align-top last:border-0 ${unidad.activo ? '' : 'bg-slate-50 text-slate-500'}`}
    >
      <td className="p-3 text-lg font-bold">{unidad.numero_economico}</td>
      <td className="p-3 font-mono">{unidad.placas}</td>
      <td className="p-3">{vehiculo || <span className="text-slate-400">Sin datos</span>}</td>
      <td className="p-3">{unidad.sitio?.nombre}</td>
      <td className="p-3">
        {!unidad.activo ? (
          <Insignia color="oscuro">Inactiva</Insignia>
        ) : conductor ? (
          <div>
            <Insignia color="verde">En servicio</Insignia>
            <p className="mt-1 text-sm text-slate-600">{conductor}</p>
          </div>
        ) : (
          <Insignia color="gris">Libre</Insignia>
        )}
        <MensajeError>{guardar.error && mensajeDeError(guardar.error)}</MensajeError>
      </td>
      <td className="p-3">
        <div className="flex flex-wrap gap-2">
          <Boton variante="secundario" onClick={onEditar}>
            Editar
          </Boton>
          <Boton
            variante="secundario"
            disabled={guardar.isPending}
            onClick={() =>
              guardar.mutate({
                id: unidad.id,
                datos: {
                  sitio_id: unidad.sitio_id,
                  numero_economico: unidad.numero_economico,
                  placas: unidad.placas,
                  activo: !unidad.activo,
                },
              })
            }
          >
            {unidad.activo ? 'Desactivar' : 'Activar'}
          </Boton>
        </div>
      </td>
    </tr>
  )
}

type PropsSitios = {
  sitios: Sitio[]
  // undefined mientras cargan: no se muestra un conteo falso de 0.
  unidades: Unidad[] | undefined
  cargando: boolean
  error: Error | null
  onAgregar: () => void
  onEditar: (sitio: Sitio) => void
}

function SeccionSitios({ sitios, unidades, cargando, error, onAgregar, onEditar }: PropsSitios) {
  const guardar = useGuardarSitio()

  return (
    <div className="space-y-4">
      <header className="flex flex-wrap items-center justify-between gap-4">
        <h2 className="text-2xl font-bold">Sitios</h2>
        <Boton variante="secundario" onClick={onAgregar}>
          Agregar sitio
        </Boton>
      </header>

      <MensajeError>{(error && mensajeDeError(error)) || (guardar.error && mensajeDeError(guardar.error))}</MensajeError>

      {cargando ? (
        <p className="text-slate-500">Cargando…</p>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {sitios.map((s) => {
            const activas = unidades?.filter((u) => u.sitio_id === s.id && u.activo).length
            return (
              <li
                key={s.id}
                data-prueba={`sitio-${s.nombre}`}
                className={`space-y-3 rounded-xl p-4 ring-1 ring-slate-200 ${s.activo ? 'bg-white' : 'bg-slate-50 text-slate-500'}`}
              >
                <div>
                  <p className="text-lg font-semibold">
                    {s.nombre} {!s.activo && <Insignia color="oscuro">Inactivo</Insignia>}
                  </p>
                  <p className="text-sm text-slate-600">
                    {[activas !== undefined && `${activas} unidad(es) activa(s)`, s.telefono && formatoTelefono(s.telefono)]
                      .filter(Boolean)
                      .join(' · ')}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Boton variante="secundario" onClick={() => onEditar(s)}>
                    Editar
                  </Boton>
                  <Boton
                    variante="secundario"
                    disabled={guardar.isPending}
                    onClick={() =>
                      guardar.mutate({
                        id: s.id,
                        datos: { nombre: s.nombre, telefono: s.telefono, activo: !s.activo },
                      })
                    }
                  >
                    {s.activo ? 'Desactivar' : 'Activar'}
                  </Boton>
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
