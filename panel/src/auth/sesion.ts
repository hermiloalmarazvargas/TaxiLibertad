import { createContext, useContext } from 'react'
import type { Database } from '../types/database'

export type Rol = Database['public']['Enums']['rol_usuario']

export type Usuario = {
  id: string
  nombre: string
  rol: Rol
  // null = despacho central (ve todos los sitios)
  sitioId: number | null
}

export type Sesion = {
  usuario: Usuario | null
  cargando: boolean
  iniciarSesion: (usuario: string, password: string) => Promise<void>
  cerrarSesion: () => Promise<void>
}

export const ROLES_DEL_PANEL: Rol[] = ['despachador', 'admin']

export const SesionContext = createContext<Sesion | null>(null)

export function useSesion(): Sesion {
  const sesion = useContext(SesionContext)
  if (!sesion) throw new Error('useSesion debe usarse dentro de <SesionProvider>')
  return sesion
}
