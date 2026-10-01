import { useState, type FormEvent } from 'react'
import { MensajeError } from '../../componentes/Avisos'
import { Boton } from '../../componentes/Boton'
import { Campo, Selector } from '../../componentes/Campo'
import { mensajeDeError } from '../../lib/errores'
import { useAltaConductor, useSitios, type CuentaCreada } from './api'
import { sugerirUsuario, USUARIO_VALIDO } from './usuario'

type Props = {
  onCreado: (cuenta: CuentaCreada) => void
  onCancelar: () => void
}

export function FormularioAlta({ onCreado, onCancelar }: Props) {
  const sitios = useSitios()
  const alta = useAltaConductor()

  const [nombre, setNombre] = useState('')
  const [usuario, setUsuario] = useState('')
  const [usuarioEditado, setUsuarioEditado] = useState(false)
  const [telefono, setTelefono] = useState('')
  const [sitioId, setSitioId] = useState('')
  const [password, setPassword] = useState('')

  // Con un solo sitio no hay nada que elegir.
  const sitioElegido = sitioId || (sitios.data?.length === 1 ? String(sitios.data[0].id) : '')
  const usuarioFinal = usuarioEditado ? usuario : sugerirUsuario(nombre)

  async function enviar(e: FormEvent) {
    e.preventDefault()
    const cuenta = await alta
      .mutateAsync({
        nombre: nombre.trim(),
        usuario: usuarioFinal,
        sitio_id: Number(sitioElegido),
        telefono: telefono.trim() || null,
        password: password || null,
      })
      .catch(() => null)
    if (cuenta) onCreado(cuenta)
  }

  return (
    <form onSubmit={enviar} className="space-y-4">
      <Campo
        etiqueta="Nombre completo"
        required
        minLength={2}
        maxLength={80}
        value={nombre}
        onChange={(e) => setNombre(e.target.value)}
        autoFocus
      />
      <Campo
        etiqueta="Usuario para iniciar sesión"
        required
        pattern={USUARIO_VALIDO.source}
        title="3 a 30 caracteres: minúsculas, números, punto o guion bajo"
        autoCapitalize="none"
        value={usuarioFinal}
        onChange={(e) => {
          setUsuarioEditado(true)
          setUsuario(e.target.value.toLowerCase())
        }}
        ayuda="Minúsculas, números, punto o guion bajo. Ej.: juan.perez"
      />
      <Campo
        etiqueta="Teléfono (opcional)"
        type="tel"
        inputMode="tel"
        value={telefono}
        onChange={(e) => setTelefono(e.target.value)}
        ayuda="10 dígitos"
      />
      <Selector etiqueta="Sitio" required value={sitioElegido} onChange={(e) => setSitioId(e.target.value)}>
        <option value="" disabled>
          {sitios.isPending ? 'Cargando…' : 'Elige el sitio'}
        </option>
        {sitios.data?.map((s) => (
          <option key={s.id} value={s.id}>
            {s.nombre}
          </option>
        ))}
      </Selector>
      <Campo
        etiqueta="Contraseña (opcional)"
        type="text"
        autoComplete="off"
        minLength={8}
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        ayuda="Déjala vacía para generar una fácil de dictar."
      />

      <MensajeError>{alta.error && mensajeDeError(alta.error)}</MensajeError>

      <div className="flex flex-wrap justify-end gap-3">
        <Boton type="button" variante="secundario" onClick={onCancelar}>
          Cancelar
        </Boton>
        <Boton type="submit" disabled={alta.isPending}>
          {alta.isPending ? 'Creando…' : 'Dar de alta'}
        </Boton>
      </div>
    </form>
  )
}
