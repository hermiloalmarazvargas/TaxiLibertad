import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useSesion } from '../../auth/sesion'
import { mensajeDeError } from '../../lib/errores'
import { supabase } from '../../lib/supabase'

async function cargarBloqueos() {
  const { data, error } = await supabase
    .from('telefonos_bloqueados')
    .select('telefono, motivo, bloqueado_en, quien:perfiles ( nombre )')
    .order('bloqueado_en', { ascending: false })
  if (error) throw error

  // Si el número es de un pasajero registrado, mostrar su nombre ayuda a
  // reconocerlo cuando vuelva a llamar.
  const telefonos = data.map((b) => b.telefono)
  const pasajeros = new Map<string, string>()
  if (telefonos.length) {
    const { data: perfiles, error: e2 } = await supabase
      .from('perfiles')
      .select('telefono, nombre')
      .eq('rol', 'pasajero')
      .in('telefono', telefonos)
    if (e2) throw e2
    for (const p of perfiles) if (p.telefono) pasajeros.set(p.telefono, p.nombre)
  }

  return data.map((b) => ({ ...b, pasajero: pasajeros.get(b.telefono) ?? null }))
}

export type Bloqueo = Awaited<ReturnType<typeof cargarBloqueos>>[number]

const CLAVE = ['bloqueos'] as const

export function useBloqueos() {
  return useQuery({ queryKey: CLAVE, queryFn: cargarBloqueos })
}

export function useBloquear() {
  const queryClient = useQueryClient()
  const { usuario } = useSesion()
  return useMutation({
    mutationFn: async ({ telefono, motivo }: { telefono: string; motivo: string }) => {
      const { error } = await supabase
        .from('telefonos_bloqueados')
        // bloqueado_por debe ser quien bloquea (lo exige RLS).
        .insert({ telefono, motivo, bloqueado_por: usuario?.id })
      if (error?.code === '23505') throw new Error('Ese número ya está bloqueado')
      if (error) throw new Error(mensajeDeError(error))
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: CLAVE }),
  })
}

export function useDesbloquear() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (telefono: string) => {
      const { error } = await supabase.from('telefonos_bloqueados').delete().eq('telefono', telefono)
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: CLAVE }),
  })
}
