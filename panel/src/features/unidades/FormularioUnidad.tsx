import { useState, type FormEvent } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo, Selector } from '../../componentes/Campo'
import { mensajeDeError } from '../../lib/errores'
import { useGuardarUnidad, type Sitio, type Unidad } from './api'

type Props = {
  unidad?: Unidad
  sitios: Sitio[]
  onListo: () => void
}

export function FormularioUnidad({ unidad, sitios, onListo }: Props) {
  const guardar = useGuardarUnidad()
  const activos = sitios.filter((s) => s.activo || s.id === unidad?.sitio_id)

  const [sitioId, setSitioId] = useState(String(unidad?.sitio_id ?? (activos.length === 1 ? activos[0].id : '')))
  const [numero, setNumero] = useState(unidad?.numero_economico ?? '')
  const [placas, setPlacas] = useState(unidad?.placas ?? '')
  const [marca, setMarca] = useState(unidad?.marca ?? '')
  const [modelo, setModelo] = useState(unidad?.modelo ?? '')
  const [color, setColor] = useState(unidad?.color ?? '')

  function enviar(e: FormEvent) {
    e.preventDefault()
    guardar.mutate(
      {
        id: unidad?.id,
        datos: {
          sitio_id: Number(sitioId),
          numero_economico: numero.trim(),
          placas: placas.trim().toUpperCase(),
          marca: marca.trim() || null,
          modelo: modelo.trim() || null,
          color: color.trim() || null,
          activo: unidad?.activo ?? true,
        },
      },
      { onSuccess: onListo },
    )
  }

  return (
    <form onSubmit={enviar} className="space-y-4">
      <Selector etiqueta="Sitio" required value={sitioId} onChange={(e) => setSitioId(e.target.value)}>
        <option value="" disabled>
          Elige el sitio
        </option>
        {activos.map((s) => (
          <option key={s.id} value={s.id}>
            {s.nombre}
          </option>
        ))}
      </Selector>
      <div className="grid gap-4 sm:grid-cols-2">
        <Campo
          etiqueta="Número económico"
          required
          value={numero}
          onChange={(e) => setNumero(e.target.value)}
          autoFocus
        />
        <Campo
          etiqueta="Placas"
          required
          autoCapitalize="characters"
          value={placas}
          onChange={(e) => setPlacas(e.target.value.toUpperCase())}
        />
        <Campo etiqueta="Marca" value={marca} onChange={(e) => setMarca(e.target.value)} />
        <Campo etiqueta="Modelo" value={modelo} onChange={(e) => setModelo(e.target.value)} />
      </div>
      <Campo
        etiqueta="Color"
        value={color}
        onChange={(e) => setColor(e.target.value)}
        ayuda="Ayuda al pasajero a reconocer el taxi. Ej.: Blanco con rojo"
      />

      <MensajeError>{guardar.error && mensajeDeError(guardar.error)}</MensajeError>

      <div className="flex flex-wrap justify-end gap-3">
        <Boton type="button" variante="secundario" onClick={onListo}>
          Cancelar
        </Boton>
        <Boton type="submit" disabled={guardar.isPending}>
          {guardar.isPending ? 'Guardando…' : 'Guardar'}
        </Boton>
      </div>
    </form>
  )
}
