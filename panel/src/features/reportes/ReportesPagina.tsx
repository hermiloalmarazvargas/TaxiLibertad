import { useState, type ReactNode } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo } from '../../componentes/Campo'
import { descargarCsv } from '../../lib/csv'
import { mensajeDeError } from '../../lib/errores'
import { etiquetaDia, hoy, inicioDeMes, sumarDias } from '../../lib/fechas'
import { useReportePorConductor, useReportePorDia, type FilaConductor, type FilaDia, type Rango } from './api'

const pesos = new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' })

function rangosRapidos(): { nombre: string; rango: Rango }[] {
  const h = hoy()
  return [
    { nombre: 'Hoy', rango: { desde: h, hasta: h } },
    { nombre: 'Ayer', rango: { desde: sumarDias(h, -1), hasta: sumarDias(h, -1) } },
    { nombre: 'Últimos 7 días', rango: { desde: sumarDias(h, -6), hasta: h } },
    { nombre: 'Este mes', rango: { desde: inicioDeMes(h), hasta: h } },
  ]
}

export function ReportesPagina() {
  const rapidos = rangosRapidos()
  const [rango, setRango] = useState<Rango>(rapidos[2].rango)
  const valido = rango.desde && rango.hasta && rango.desde <= rango.hasta

  return (
    <section className="space-y-8">
      <header className="space-y-4">
        <h1 className="text-2xl font-bold">Reportes</h1>

        <div className="flex flex-wrap gap-2">
          {rapidos.map((r) => {
            const activo = r.rango.desde === rango.desde && r.rango.hasta === rango.hasta
            return (
              <Boton
                key={r.nombre}
                variante={activo ? 'primario' : 'secundario'}
                aria-pressed={activo}
                onClick={() => setRango(r.rango)}
              >
                {r.nombre}
              </Boton>
            )
          })}
        </div>

        <div className="flex max-w-md flex-wrap gap-4">
          <div className="flex-1">
            <Campo
              etiqueta="Desde"
              type="date"
              value={rango.desde}
              max={rango.hasta}
              onChange={(e) => setRango({ ...rango, desde: e.target.value })}
            />
          </div>
          <div className="flex-1">
            <Campo
              etiqueta="Hasta"
              type="date"
              value={rango.hasta}
              min={rango.desde}
              onChange={(e) => setRango({ ...rango, hasta: e.target.value })}
            />
          </div>
        </div>
      </header>

      {valido ? (
        <>
          <ReportePorDia rango={rango} />
          <ReportePorConductor rango={rango} />
        </>
      ) : (
        <MensajeError>Elige un rango de fechas válido.</MensajeError>
      )}
    </section>
  )
}

// ── Por día ─────────────────────────────────────────────────────────

function ReportePorDia({ rango }: { rango: Rango }) {
  const reporte = useReportePorDia(rango)
  const filas = reporte.data ?? []

  const total = (campo: keyof FilaDia) => filas.reduce((suma, f) => suma + Number(f[campo] ?? 0), 0)
  // Aproximación: promedio de los promedios diarios (no pondera por el
  // número de viajes de cada día).
  const conAsignacion = filas.filter((f) => f.minutos_asignacion != null)
  const minutosPromedio = conAsignacion.length
    ? conAsignacion.reduce((s, f) => s + Number(f.minutos_asignacion), 0) / conAsignacion.length
    : null

  function exportar() {
    descargarCsv(
      `viajes-por-dia_${rango.desde}_${rango.hasta}.csv`,
      ['Fecha', 'Solicitados', 'Completados', 'Cancelados', 'Cancelados por pasajero', 'Sin conductor', 'Por teléfono', 'Ingresos estimados', 'A convenir', 'Minutos para asignar'],
      filas.map((f) => [f.fecha, f.solicitados, f.completados, f.cancelados, f.cancelados_pasajero, f.sin_conductor, f.por_telefono, f.ingresos, f.a_convenir, f.minutos_asignacion]),
    )
  }

  return (
    <Seccion
      titulo="Viajes por día"
      error={reporte.error}
      cargando={reporte.isPending}
      onExportar={filas.length ? exportar : undefined}
      nota="Ingresos estimados: suma de las tarifas de los viajes completados. Los viajes «a convenir» no tienen monto y se cuentan aparte."
    >
      <table className="w-full min-w-[52rem] text-right" data-prueba="reporte-dia">
        <thead className="border-b border-slate-200 text-sm text-slate-600">
          <tr>
            <th className="p-3 text-left font-semibold">Fecha</th>
            <th className="p-3 font-semibold">Solicitados</th>
            <th className="p-3 font-semibold">Completados</th>
            <th className="p-3 font-semibold">Cancelados</th>
            <th className="p-3 font-semibold">Sin conductor</th>
            <th className="p-3 font-semibold">Por teléfono</th>
            <th className="p-3 font-semibold">Ingresos est.</th>
            <th className="p-3 font-semibold">A convenir</th>
            <th className="p-3 font-semibold">Min. para asignar</th>
          </tr>
        </thead>
        <tbody className="tabular-nums">
          {filas.map((f) => (
            <tr key={f.fecha} className="border-b border-slate-100">
              <td className="p-3 text-left whitespace-nowrap">{etiquetaDia(f.fecha)}</td>
              <td className="p-3">{f.solicitados}</td>
              <td className="p-3">{f.completados}</td>
              <td className="p-3">
                {f.cancelados}
                {f.cancelados > 0 && <span className="text-sm text-slate-500"> ({f.cancelados_pasajero} pasajero)</span>}
              </td>
              <td className="p-3">{f.sin_conductor}</td>
              <td className="p-3">{f.por_telefono}</td>
              <td className="p-3">{pesos.format(Number(f.ingresos))}</td>
              <td className="p-3">{f.a_convenir}</td>
              <td className="p-3">{f.minutos_asignacion ?? '—'}</td>
            </tr>
          ))}
        </tbody>
        <tfoot className="font-bold tabular-nums">
          <tr data-prueba="total-dia">
            <td className="p-3 text-left">Total</td>
            <td className="p-3">{total('solicitados')}</td>
            <td className="p-3">{total('completados')}</td>
            <td className="p-3">{total('cancelados')}</td>
            <td className="p-3">{total('sin_conductor')}</td>
            <td className="p-3">{total('por_telefono')}</td>
            <td className="p-3">{pesos.format(total('ingresos'))}</td>
            <td className="p-3">{total('a_convenir')}</td>
            <td className="p-3">{minutosPromedio == null ? '—' : minutosPromedio.toFixed(1)}</td>
          </tr>
        </tfoot>
      </table>
    </Seccion>
  )
}

// ── Por conductor ───────────────────────────────────────────────────

function tasaAceptacion(f: FilaConductor): string {
  const respondidas = f.aceptadas + f.rechazadas + f.vencidas
  return respondidas ? `${Math.round((f.aceptadas / respondidas) * 100)} %` : '—'
}

function ReportePorConductor({ rango }: { rango: Rango }) {
  const reporte = useReportePorConductor(rango)
  const filas = reporte.data ?? []

  function exportar() {
    descargarCsv(
      `viajes-por-conductor_${rango.desde}_${rango.hasta}.csv`,
      ['Conductor', 'Sitio', 'Completados', 'Ingresos estimados', 'A convenir', 'Ofertas', 'Aceptadas', 'Rechazadas', 'Vencidas', 'Soltados', 'Aceptación'],
      filas.map((f) => [f.nombre, f.sitio, f.completados, f.ingresos, f.a_convenir, f.ofertas, f.aceptadas, f.rechazadas, f.vencidas, f.soltados, tasaAceptacion(f)]),
    )
  }

  return (
    <Seccion
      titulo="Por conductor"
      error={reporte.error}
      cargando={reporte.isPending}
      onExportar={filas.length ? exportar : undefined}
      nota="Vencidas: ofertas que el conductor dejó pasar sin responder. Soltados: viajes que aceptó y después liberó."
    >
      <table className="w-full min-w-[56rem] text-right" data-prueba="reporte-conductor">
        <thead className="border-b border-slate-200 text-sm text-slate-600">
          <tr>
            <th className="p-3 text-left font-semibold">Conductor</th>
            <th className="p-3 font-semibold">Completados</th>
            <th className="p-3 font-semibold">Ingresos est.</th>
            <th className="p-3 font-semibold">A convenir</th>
            <th className="p-3 font-semibold">Ofertas</th>
            <th className="p-3 font-semibold">Aceptadas</th>
            <th className="p-3 font-semibold">Rechazadas</th>
            <th className="p-3 font-semibold">Vencidas</th>
            <th className="p-3 font-semibold">Soltados</th>
            <th className="p-3 font-semibold">Aceptación</th>
          </tr>
        </thead>
        <tbody className="tabular-nums">
          {filas.length === 0 && (
            <tr>
              <td colSpan={10} className="p-3 text-left text-slate-500">
                No hay conductores.
              </td>
            </tr>
          )}
          {filas.map((f) => (
            <tr key={f.conductor_id} className={`border-b border-slate-100 ${f.activo ? '' : 'text-slate-500'}`}>
              <td className="p-3 text-left">
                <p className="font-semibold">{f.nombre}</p>
                <p className="text-sm text-slate-500">
                  {f.sitio}
                  {!f.activo && ' · desactivado'}
                </p>
              </td>
              <td className="p-3">{f.completados}</td>
              <td className="p-3">{pesos.format(Number(f.ingresos))}</td>
              <td className="p-3">{f.a_convenir}</td>
              <td className="p-3">{f.ofertas}</td>
              <td className="p-3">{f.aceptadas}</td>
              <td className="p-3">{f.rechazadas}</td>
              <td className={`p-3 ${f.vencidas > 0 ? 'font-semibold text-red-700' : ''}`}>{f.vencidas}</td>
              <td className="p-3">{f.soltados}</td>
              <td className="p-3">{tasaAceptacion(f)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Seccion>
  )
}

// ── Contenedor común ────────────────────────────────────────────────

type PropsSeccion = {
  titulo: string
  nota: string
  error: Error | null
  cargando: boolean
  onExportar?: () => void
  children: ReactNode
}

function Seccion({ titulo, nota, error, cargando, onExportar, children }: PropsSeccion) {
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-xl font-bold">{titulo}</h2>
        {onExportar && (
          <Boton variante="secundario" onClick={onExportar}>
            Descargar CSV
          </Boton>
        )}
      </div>
      <MensajeError>{error && mensajeDeError(error)}</MensajeError>
      {cargando ? (
        <p className="text-slate-500">Cargando…</p>
      ) : (
        <div className="overflow-x-auto rounded-xl bg-white ring-1 ring-slate-200">{children}</div>
      )}
      <p className="max-w-prose text-sm text-slate-500">{nota}</p>
    </div>
  )
}
