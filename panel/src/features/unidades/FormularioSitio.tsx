import { useState, type FormEvent } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo } from '../../componentes/Campo'
import { mensajeDeError } from '../../lib/errores'
import { formatoTelefono, normalizarTelefono } from '../../lib/formato'
import { useGuardarSitio, type Sitio } from './api'

type Props = { sitio?: Sitio; onListo: () => void }

export function FormularioSitio({ sitio, onListo }: Props) {
  const guardar = useGuardarSitio()
  const [nombre, setNombre] = useState(sitio?.nombre ?? '')
  const [telefono, setTelefono] = useState(formatoTelefono(sitio?.telefono))
  const [errorTelefono, setErrorTelefono] = useState<string | null>(null)

  function enviar(e: FormEvent) {
    e.preventDefault()
    const normalizado = telefono.trim() ? normalizarTelefono(telefono) : null
    if (telefono.trim() && !normalizado) {
      setErrorTelefono('El teléfono debe tener 10 dígitos')
      return
    }
    setErrorTelefono(null)
    guardar.mutate(
      { id: sitio?.id, datos: { nombre: nombre.trim(), telefono: normalizado, activo: sitio?.activo ?? true } },
      { onSuccess: onListo },
    )
  }

  return (
    <form onSubmit={enviar} className="space-y-4">
      <Campo etiqueta="Nombre del sitio" required value={nombre} onChange={(e) => setNombre(e.target.value)} autoFocus />
      <Campo
        etiqueta="Teléfono del sitio (opcional)"
        type="tel"
        inputMode="tel"
        value={telefono}
        onChange={(e) => setTelefono(e.target.value)}
        ayuda="10 dígitos"
      />

      <MensajeError>{errorTelefono ?? (guardar.error && mensajeDeError(guardar.error))}</MensajeError>

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
