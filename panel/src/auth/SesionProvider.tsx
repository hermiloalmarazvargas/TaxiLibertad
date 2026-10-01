import type { Session } from '@supabase/supabase-js'
import { useEffect, useState, type ReactNode } from 'react'
import { leerClaims } from '../lib/claims'
import { supabase } from '../lib/supabase'
import { correoDeUsuario } from '../lib/usuarios'
import { ROLES_DEL_PANEL, SesionContext, type Rol, type Usuario } from './sesion'

const tieneAcceso = (rol: Rol | undefined): rol is Rol => !!rol && ROLES_DEL_PANEL.includes(rol)

export function SesionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [usuario, setUsuario] = useState<Usuario | null>(null)
  const [cargando, setCargando] = useState(true)

  // Escucha inicio/cierre de sesión y la renovación del token (≈ cada hora).
  // No se hacen consultas dentro del callback (puede bloquear a supabase-js);
  // el efecto de abajo reacciona al cambio.
  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((_evento, nueva) => {
      setSession(nueva)
      if (!nueva) {
        setUsuario(null)
        setCargando(false)
      }
    })
    return () => data.subscription.unsubscribe()
  }, [])

  const accessToken = session?.access_token
  const userId = session?.user.id

  useEffect(() => {
    if (!accessToken || !userId) return

    const { rol, sitio_id } = leerClaims(accessToken)
    if (!tieneAcceso(rol)) {
      // Por ejemplo, un conductor que abrió el panel: se cierra su sesión.
      void supabase.auth.signOut()
      return
    }

    let vigente = true
    void supabase
      .from('perfiles')
      .select('nombre')
      .eq('id', userId)
      .single()
      .then(({ data }) => {
        if (!vigente) return
        setUsuario({ id: userId, nombre: data?.nombre ?? '', rol, sitioId: sitio_id ?? null })
        setCargando(false)
      })
    return () => {
      vigente = false
    }
  }, [accessToken, userId])

  async function iniciarSesion(nombreUsuario: string, password: string) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: correoDeUsuario(nombreUsuario),
      password,
    })
    if (error) throw error
    if (!tieneAcceso(leerClaims(data.session.access_token).rol)) {
      await supabase.auth.signOut()
      throw new Error('Esta cuenta no tiene acceso al panel de despacho')
    }
  }

  async function cerrarSesion() {
    await supabase.auth.signOut()
  }

  return (
    <SesionContext.Provider value={{ usuario, cargando, iniciarSesion, cerrarSesion }}>
      {children}
    </SesionContext.Provider>
  )
}
