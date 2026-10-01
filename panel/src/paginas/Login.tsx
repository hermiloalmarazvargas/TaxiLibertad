import { useState, type FormEvent } from 'react'
import { Navigate, useLocation } from 'react-router'
import { useSesion } from '../auth/sesion'
import { Boton } from '../componentes/Boton'
import { mensajeDeError } from '../lib/errores'

export function Login() {
  const { usuario, iniciarSesion } = useSesion()
  const location = useLocation()
  const [nombreUsuario, setNombreUsuario] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  if (usuario) {
    const desde = (location.state as { desde?: string } | null)?.desde ?? '/'
    return <Navigate to={desde} replace />
  }

  async function enviar(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setEnviando(true)
    try {
      await iniciarSesion(nombreUsuario, password)
    } catch (err) {
      setError(mensajeDeError(err))
    } finally {
      setEnviando(false)
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <form onSubmit={enviar} className="w-full max-w-sm space-y-5 rounded-2xl bg-white p-8 shadow-sm ring-1 ring-slate-200">
        <div>
          <h1 className="text-2xl font-bold">Taxi Miahuatlán</h1>
          <p className="text-slate-600">Panel de despacho</p>
        </div>

        <label className="block">
          <span className="font-medium">Usuario</span>
          <input
            className="mt-1 block min-h-12 w-full rounded-lg border border-slate-300 px-3 text-lg"
            autoComplete="username"
            autoCapitalize="none"
            required
            value={nombreUsuario}
            onChange={(e) => setNombreUsuario(e.target.value)}
          />
        </label>

        <label className="block">
          <span className="font-medium">Contraseña</span>
          <input
            className="mt-1 block min-h-12 w-full rounded-lg border border-slate-300 px-3 text-lg"
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </label>

        {error && (
          <p className="rounded-lg bg-red-50 p-3 text-red-800 ring-1 ring-red-200" role="alert">
            {error}
          </p>
        )}

        <Boton type="submit" className="w-full" disabled={enviando}>
          {enviando ? 'Entrando…' : 'Entrar'}
        </Boton>
      </form>
    </main>
  )
}
