import type { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router'
import { Cargando } from '../componentes/Cargando'
import { useSesion, type Rol } from './sesion'

type Props = {
  children: ReactNode
  // Si se indica, solo esos roles pueden entrar (p. ej. solo admin).
  roles?: Rol[]
}

// Oculta pantallas según la sesión. Es solo para la interfaz: aunque alguien
// forzara la ruta, RLS no le devolvería datos que no le corresponden.
export function RutaProtegida({ children, roles }: Props) {
  const { usuario, cargando } = useSesion()
  const location = useLocation()

  if (cargando) return <Cargando />
  if (!usuario) return <Navigate to="/login" replace state={{ desde: location.pathname }} />
  if (roles && !roles.includes(usuario.rol)) return <Navigate to="/" replace />

  return children
}
