import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'

export type Rango = { desde: string; hasta: string }

export function useReportePorDia({ desde, hasta }: Rango) {
  return useQuery({
    queryKey: ['reportes', 'dia', desde, hasta],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('reporte_por_dia', { p_desde: desde, p_hasta: hasta })
      if (error) throw error
      return data
    },
    // Al cambiar de rango se siguen viendo los datos anteriores mientras carga.
    placeholderData: keepPreviousData,
  })
}

export function useReportePorConductor({ desde, hasta }: Rango) {
  return useQuery({
    queryKey: ['reportes', 'conductor', desde, hasta],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('reporte_por_conductor', { p_desde: desde, p_hasta: hasta })
      if (error) throw error
      return data
    },
    placeholderData: keepPreviousData,
  })
}

export type FilaDia = NonNullable<ReturnType<typeof useReportePorDia>['data']>[number]
export type FilaConductor = NonNullable<ReturnType<typeof useReportePorConductor>['data']>[number]
