import { useState } from 'react'
import { useSesion } from '../../auth/sesion'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Modal } from '../../componentes/Modal'
import { mensajeDeError } from '../../lib/errores'
import { formatoTelefono } from '../../lib/formato'
import { useAhora } from '../../lib/useAhora'
import {
  useCambiarActivo,
  useConductores,
  useConductoresEnVivo,
  useRestablecerPassword,
  type Conductor,
  type CuentaCreada,
} from './api'
import { ContrasenaNueva } from './ContrasenaNueva'
import { EstadoConductor } from './EstadoConductor'
import { FormularioAlta } from './FormularioAlta'

type Dialogo =
  | { tipo: 'alta' }
  | { tipo: 'cuenta'; titulo: string; cuenta: Omit<CuentaCreada, 'id'> }
  | { tipo: 'restablecer'; conductor: Conductor }
  | { tipo: 'activo'; conductor: Conductor }

export function ConductoresPagina() {
  const { usuario } = useSesion()
  const esAdmin = usuario?.rol === 'admin'
  const conductores = useConductores()
  useConductoresEnVivo()
  const ahora = useAhora(15_000)

  const [busqueda, setBusqueda] = useState('')
  const [dialogo, setDialogo] = useState<Dialogo | null>(null)
  const cerrar = () => setDialogo(null)

  const texto = busqueda.trim().toLowerCase()
  const visibles = (conductores.data ?? []).filter(
    (c) =>
      !texto ||
      c.perfil?.nombre.toLowerCase().includes(texto) ||
      c.perfil?.usuario?.includes(texto) ||
      c.estado?.unidad?.numero_economico.toLowerCase().includes(texto),
  )

  return (
    <section className="space-y-6">
      <header className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-bold">Conductores</h1>
        {esAdmin && <Boton onClick={() => setDialogo({ tipo: 'alta' })}>Dar de alta</Boton>}
      </header>

      <input
        type="search"
        placeholder="Buscar por nombre, usuario o unidad"
        aria-label="Buscar conductor"
        className="block min-h-12 w-full max-w-md rounded-lg border border-slate-300 bg-white px-3 text-lg"
        value={busqueda}
        onChange={(e) => setBusqueda(e.target.value)}
      />

      <MensajeError>{conductores.error && mensajeDeError(conductores.error)}</MensajeError>

      {conductores.isPending ? (
        <p className="text-slate-500">Cargando…</p>
      ) : visibles.length === 0 ? (
        <p className="text-slate-500">{texto ? 'Ningún conductor coincide.' : 'Aún no hay conductores.'}</p>
      ) : (
        <div className="overflow-x-auto rounded-xl bg-white ring-1 ring-slate-200">
          <table className="w-full min-w-[44rem] text-left">
            <thead className="border-b border-slate-200 text-sm text-slate-600">
              <tr>
                <th className="p-3 font-semibold">Conductor</th>
                <th className="p-3 font-semibold">Sitio</th>
                <th className="p-3 font-semibold">Teléfono</th>
                <th className="p-3 font-semibold">Estado</th>
                {esAdmin && <th className="p-3 font-semibold">Acciones</th>}
              </tr>
            </thead>
            <tbody>
              {visibles.map((c) => (
                <tr
                  key={c.perfil_id}
                  data-prueba={`conductor-${c.perfil?.usuario}`}
                  className={`border-b border-slate-100 last:border-0 ${c.activo ? '' : 'bg-slate-50 text-slate-500'}`}
                >
                  <td className="p-3">
                    <p className="font-semibold">{c.perfil?.nombre}</p>
                    <p className="text-sm text-slate-500">{c.perfil?.usuario}</p>
                  </td>
                  <td className="p-3">{c.sitio?.nombre}</td>
                  <td className="p-3 whitespace-nowrap">{formatoTelefono(c.perfil?.telefono)}</td>
                  <td className="p-3">
                    <EstadoConductor conductor={c} ahora={ahora} />
                  </td>
                  {esAdmin && (
                    <td className="p-3">
                      <div className="flex flex-wrap gap-2">
                        <Boton variante="secundario" onClick={() => setDialogo({ tipo: 'restablecer', conductor: c })}>
                          Nueva contraseña
                        </Boton>
                        <Boton
                          variante={c.activo ? 'peligro' : 'secundario'}
                          onClick={() => setDialogo({ tipo: 'activo', conductor: c })}
                        >
                          {c.activo ? 'Desactivar' : 'Reactivar'}
                        </Boton>
                      </div>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Modal abierto={dialogo?.tipo === 'alta'} titulo="Dar de alta conductor" onCerrar={cerrar}>
        <FormularioAlta
          onCancelar={cerrar}
          onCreado={(cuenta) => setDialogo({ tipo: 'cuenta', titulo: 'Conductor dado de alta', cuenta })}
        />
      </Modal>

      <Modal
        abierto={dialogo?.tipo === 'cuenta'}
        titulo={dialogo?.tipo === 'cuenta' ? dialogo.titulo : ''}
        onCerrar={cerrar}
        soloConBoton
      >
        {dialogo?.tipo === 'cuenta' && (
          <ContrasenaNueva usuario={dialogo.cuenta.usuario} password={dialogo.cuenta.password} onListo={cerrar} />
        )}
      </Modal>

      <Modal abierto={dialogo?.tipo === 'restablecer'} titulo="Nueva contraseña" onCerrar={cerrar}>
        {dialogo?.tipo === 'restablecer' && (
          <ConfirmarRestablecer
            conductor={dialogo.conductor}
            onCancelar={cerrar}
            onListo={(cuenta) => setDialogo({ tipo: 'cuenta', titulo: 'Contraseña restablecida', cuenta })}
          />
        )}
      </Modal>

      <Modal
        abierto={dialogo?.tipo === 'activo'}
        titulo={dialogo?.tipo === 'activo' && dialogo.conductor.activo ? 'Desactivar conductor' : 'Reactivar conductor'}
        onCerrar={cerrar}
      >
        {dialogo?.tipo === 'activo' && <ConfirmarActivo conductor={dialogo.conductor} onListo={cerrar} />}
      </Modal>
    </section>
  )
}

function ConfirmarRestablecer({
  conductor,
  onCancelar,
  onListo,
}: {
  conductor: Conductor
  onCancelar: () => void
  onListo: (cuenta: { usuario: string; password: string }) => void
}) {
  const restablecer = useRestablecerPassword()
  return (
    <div className="space-y-4">
      <p>
        Se generará una contraseña nueva para <strong>{conductor.perfil?.nombre}</strong>. La anterior dejará de
        funcionar.
      </p>
      <MensajeError>{restablecer.error && mensajeDeError(restablecer.error)}</MensajeError>
      <div className="flex flex-wrap justify-end gap-3">
        <Boton variante="secundario" onClick={onCancelar}>
          Cancelar
        </Boton>
        <Boton
          disabled={restablecer.isPending}
          onClick={() => restablecer.mutate(conductor.perfil_id, { onSuccess: onListo })}
        >
          {restablecer.isPending ? 'Generando…' : 'Generar contraseña'}
        </Boton>
      </div>
    </div>
  )
}

function ConfirmarActivo({ conductor, onListo }: { conductor: Conductor; onListo: () => void }) {
  const cambiar = useCambiarActivo()
  const desactivar = conductor.activo
  return (
    <div className="space-y-4">
      {desactivar ? (
        <p>
          <strong>{conductor.perfil?.nombre}</strong> quedará fuera de servicio y no podrá iniciar sesión ni recibir
          viajes hasta que lo reactives.
        </p>
      ) : (
        <p>
          <strong>{conductor.perfil?.nombre}</strong> podrá volver a iniciar sesión y ponerse disponible.
        </p>
      )}
      <MensajeError>{cambiar.error && mensajeDeError(cambiar.error)}</MensajeError>
      <div className="flex flex-wrap justify-end gap-3">
        <Boton variante="secundario" onClick={onListo}>
          Cancelar
        </Boton>
        <Boton
          variante={desactivar ? 'peligro' : 'primario'}
          disabled={cambiar.isPending}
          onClick={() => cambiar.mutate({ perfilId: conductor.perfil_id, activo: !desactivar }, { onSuccess: onListo })}
        >
          {desactivar ? 'Desactivar' : 'Reactivar'}
        </Boton>
      </div>
    </div>
  )
}
