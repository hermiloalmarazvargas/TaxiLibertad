import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect } from 'react'
import { invocarFuncion } from '../../lib/funciones'
import { supabase } from '../../lib/supabase'
import type { Database } from '../../types/database'

type EstadoFila = Database['public']['Tables']['conductor_estado']['Row']

const CONSULTA_CONDUCTORES = `
  perfil_id, activo,
  sitio:sitios ( id, nombre ),
  perfil:perfiles ( nombre, usuario, telefono ),
  estado:conductor_estado (
    estado, motivo_fuera, fuera_desde, ofertas_vencidas_seguidas, ubicacion_en, unidad_id,
    unidad:unidades ( numero_economico )
  )
` as const

async function cargarConductores() {
  const { data, error } = await supabase.from('conductores').select(CONSULTA_CONDUCTORES)
  if (error) throw error
  return data.sort((a, b) => (a.perfil?.nombre ?? '').localeCompare(b.perfil?.nombre ?? '', 'es'))
}

export type Conductor = Awaited<ReturnType<typeof cargarConductores>>[number]

const CLAVE = ['conductores'] as const

export function useConductores() {
  return useQuery({ queryKey: CLAVE, queryFn: cargarConductores })
}

// Mantiene la lista al día con Realtime. Las actualizaciones de ubicación
// (cada pocos segundos) solo se aplican en la caché sin volver a consultar;
// si cambia la unidad se recarga para obtener su número económico.
export function useConductoresEnVivo() {
  const queryClient = useQueryClient()

  useEffect(() => {
    const canal = supabase
      .channel('panel-conductores')
      .on<EstadoFila>(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'conductor_estado' },
        ({ new: nuevo }) => {
          if (!nuevo || !('conductor_id' in nuevo)) return
          const lista = queryClient.getQueryData<Conductor[]>(CLAVE)
          const actual = lista?.find((c) => c.perfil_id === nuevo.conductor_id)
          if (!actual?.estado || actual.estado.unidad_id !== nuevo.unidad_id) {
            void queryClient.invalidateQueries({ queryKey: CLAVE })
            return
          }
          queryClient.setQueryData<Conductor[]>(CLAVE, (previa) =>
            previa?.map((c) =>
              c.perfil_id === nuevo.conductor_id && c.estado
                ? {
                    ...c,
                    estado: {
                      ...c.estado,
                      estado: nuevo.estado,
                      motivo_fuera: nuevo.motivo_fuera,
                      fuera_desde: nuevo.fuera_desde,
                      ofertas_vencidas_seguidas: nuevo.ofertas_vencidas_seguidas,
                      ubicacion_en: nuevo.ubicacion_en,
                    },
                  }
                : c,
            ),
          )
        },
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(canal)
    }
  }, [queryClient])
}

export function useSitios() {
  return useQuery({
    queryKey: ['sitios'],
    queryFn: async () => {
      const { data, error } = await supabase.from('sitios').select('id, nombre').eq('activo', true).order('nombre')
      if (error) throw error
      return data
    },
  })
}

export type DatosAlta = {
  nombre: string
  usuario: string
  sitio_id: number
  telefono: string | null
  password: string | null
}

export type CuentaCreada = { id: string; usuario: string; password?: string }

export function useAltaConductor() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (datos: DatosAlta) =>
      invocarFuncion<CuentaCreada>('alta-conductor', {
        ...datos,
        telefono: datos.telefono || null,
        password: datos.password || undefined,
      }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: CLAVE }),
  })
}

export function useRestablecerPassword() {
  return useMutation({
    mutationFn: (perfilId: string) =>
      invocarFuncion<{ usuario: string; password: string }>('restablecer-password', { perfil_id: perfilId }),
  })
}

export function useCambiarActivo() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ perfilId, activo }: { perfilId: string; activo: boolean }) => {
      const { error } = await supabase.rpc('cambiar_activo_conductor', {
        p_conductor_id: perfilId,
        p_activo: activo,
      })
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: CLAVE }),
  })
}
