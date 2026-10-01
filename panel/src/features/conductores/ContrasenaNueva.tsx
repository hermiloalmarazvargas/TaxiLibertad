import { useState } from 'react'
import { Boton } from '../../componentes/Boton'

type Props = {
  usuario: string
  // undefined cuando el admin escribió la contraseña él mismo.
  password?: string
  onListo: () => void
}

// Muestra la contraseña UNA sola vez: no se guarda en ningún lado del panel.
export function ContrasenaNueva({ usuario, password, onListo }: Props) {
  const [copiado, setCopiado] = useState(false)

  async function copiar() {
    await navigator.clipboard.writeText(`Usuario: ${usuario}\nContraseña: ${password}`)
    setCopiado(true)
  }

  return (
    <div className="space-y-4">
      <dl className="space-y-2 rounded-xl bg-slate-50 p-4 ring-1 ring-slate-200">
        <div>
          <dt className="text-sm text-slate-600">Usuario</dt>
          <dd className="font-mono text-xl font-semibold" data-prueba="usuario">
            {usuario}
          </dd>
        </div>
        {password && (
          <div>
            <dt className="text-sm text-slate-600">Contraseña</dt>
            <dd className="font-mono text-2xl font-semibold tracking-wider" data-prueba="password">
              {password}
            </dd>
          </div>
        )}
      </dl>

      {password ? (
        <p className="text-amber-900">
          Anótala y entrégasela al conductor en persona. <strong>No se volverá a mostrar.</strong>
        </p>
      ) : (
        <p>Entrégale al conductor la contraseña que escribiste.</p>
      )}

      <div className="flex flex-wrap justify-end gap-3">
        {password && (
          <Boton type="button" variante="secundario" onClick={() => void copiar()}>
            {copiado ? 'Copiado ✓' : 'Copiar'}
          </Boton>
        )}
        <Boton type="button" onClick={onListo}>
          Listo
        </Boton>
      </div>
    </div>
  )
}
