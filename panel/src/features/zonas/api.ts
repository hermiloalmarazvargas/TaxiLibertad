import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { MultiPolygon, Polygon } from 'geojson'
import { mensajeDeError } from '../../lib/errores'
import { supabase } from '../../lib/supabase'

// ── Zonas ───────────────────────────────────────────────────────────

export type Zona = {
  id: number
  nombre: string
  color: string
  activa: boolean
  // La API entrega la columna de PostGIS ya convertida a GeoJSON.
  poligono: MultiPolygon
}

async function cargarZonas(): Promise<Zona[]> {
  const { data, error } = await supabase.from('zonas').select('id, nombre, color, activa, poligono').order('nombre')
  if (error) throw error
  return data as unknown as Zona[]
}

export function useZonas() {
  return useQuery({ queryKey: ['zonas'], queryFn: cargarZonas })
}

export type DatosZona = {
  id?: number
  nombre: string
  color: string
  forma: Polygon | MultiPolygon
}

export function useGuardarZona() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, nombre, color, forma }: DatosZona) => {
      const { error } = await supabase.rpc('guardar_zona', {
        p_nombre: nombre,
        p_color: color,
        p_geojson: forma as never,
        p_id: id,
      })
      if (error) throw new Error(mensajeDeError(error))
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['zonas'] }),
  })
}

export function useCambiarActivaZona() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, activa }: { id: number; activa: boolean }) => {
      const { error } = await supabase.from('zonas').update({ activa }).eq('id', id)
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['zonas'] }),
  })
}

// ── Tarifas ─────────────────────────────────────────────────────────

export const claveTarifa = (origen: number, destino: number) => `${origen}-${destino}`

async function cargarTarifas(): Promise<Map<string, number>> {
  const { data, error } = await supabase.from('tarifas').select('zona_origen_id, zona_destino_id, monto')
  if (error) throw error
  return new Map(data.map((t) => [claveTarifa(t.zona_origen_id, t.zona_destino_id), Number(t.monto)]))
}

export function useTarifas() {
  return useQuery({ queryKey: ['tarifas'], queryFn: cargarTarifas })
}

// monto null = quitar la tarifa ("a convenir").
export type CambioTarifa = { origen: number; destino: number; monto: number | null }

export function useGuardarTarifas() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (cambios: CambioTarifa[]) => {
      const guardar = cambios.filter((c) => c.monto != null)
      const quitar = cambios.filter((c) => c.monto == null)

      if (guardar.length) {
        const { error } = await supabase.from('tarifas').upsert(
          guardar.map((c) => ({ zona_origen_id: c.origen, zona_destino_id: c.destino, monto: c.monto! })),
          { onConflict: 'zona_origen_id,zona_destino_id' },
        )
        if (error) throw error
      }
      for (const c of quitar) {
        const { error } = await supabase
          .from('tarifas')
          .delete()
          .eq('zona_origen_id', c.origen)
          .eq('zona_destino_id', c.destino)
        if (error) throw error
      }
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['tarifas'] }),
  })
}

// ── Recargo nocturno ────────────────────────────────────────────────

export type Recargo = { porcentaje: number; desde: string; hasta: string }

export function useRecargo() {
  return useQuery({
    queryKey: ['configuracion'],
    queryFn: async (): Promise<Recargo> => {
      const { data, error } = await supabase
        .from('configuracion')
        .select('recargo_nocturno_pct, recargo_desde, recargo_hasta')
        .single()
      if (error) throw error
      return {
        porcentaje: Number(data.recargo_nocturno_pct),
        // La base devuelve "22:00:00"; el campo de hora usa "22:00".
        desde: data.recargo_desde.slice(0, 5),
        hasta: data.recargo_hasta.slice(0, 5),
      }
    },
  })
}

export function useGuardarRecargo() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ porcentaje, desde, hasta }: Recargo) => {
      const { error } = await supabase
        .from('configuracion')
        .update({ recargo_nocturno_pct: porcentaje, recargo_desde: desde, recargo_hasta: hasta })
        .eq('id', true)
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['configuracion'] }),
  })
}

// Mismo cálculo que tarifa_estimada en la base: recargo redondeado al peso.
export const recargoDe = (tarifa: number, porcentaje: number) => Math.round((tarifa * porcentaje) / 100)
