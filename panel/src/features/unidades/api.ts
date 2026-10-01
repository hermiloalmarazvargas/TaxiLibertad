import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { mensajeDeError } from '../../lib/errores'
import { supabase } from '../../lib/supabase'
import type { Database } from '../../types/database'

type Tablas = Database['public']['Tables']

// ── Sitios ──────────────────────────────────────────────────────────

async function cargarSitios() {
  const { data, error } = await supabase
    .from('sitios')
    .select('id, nombre, telefono, activo')
    .order('nombre')
  if (error) throw error
  return data
}

export type Sitio = Awaited<ReturnType<typeof cargarSitios>>[number]

// Todos los sitios (también inactivos), para administrarlos.
// La clave empieza con 'sitios' para que al invalidarla también se
// refresque la lista de sitios activos de otros formularios.
export function useTodosLosSitios() {
  return useQuery({ queryKey: ['sitios', 'todos'], queryFn: cargarSitios })
}

export type DatosSitio = Pick<Tablas['sitios']['Insert'], 'nombre' | 'telefono' | 'activo'>

export function useGuardarSitio() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, datos }: { id?: number; datos: DatosSitio }) => {
      const { error } = id
        ? await supabase.from('sitios').update(datos).eq('id', id)
        : await supabase.from('sitios').insert(datos)
      if (error) throw new Error(traducirError(error))
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['sitios'] }),
  })
}

// ── Unidades ────────────────────────────────────────────────────────

const CONSULTA_UNIDADES = `
  id, numero_economico, placas, marca, modelo, color, activo, sitio_id,
  sitio:sitios ( nombre ),
  servicio:conductor_estado ( estado, conductor:conductores ( perfil:perfiles ( nombre ) ) )
` as const

async function cargarUnidades() {
  const { data, error } = await supabase.from('unidades').select(CONSULTA_UNIDADES)
  if (error) throw error
  return data.sort(
    (a, b) =>
      (a.sitio?.nombre ?? '').localeCompare(b.sitio?.nombre ?? '', 'es') ||
      a.numero_economico.localeCompare(b.numero_economico, 'es', { numeric: true }),
  )
}

export type Unidad = Awaited<ReturnType<typeof cargarUnidades>>[number]

// Nombre del conductor que trae la unidad en servicio, si hay.
export function conductorEnServicio(unidad: Unidad): string | null {
  const activo = unidad.servicio.find((s) => s.estado !== 'fuera_de_servicio')
  return activo?.conductor?.perfil?.nombre ?? null
}

export function useUnidades() {
  return useQuery({ queryKey: ['unidades'], queryFn: cargarUnidades })
}

export type DatosUnidad = Pick<
  Tablas['unidades']['Insert'],
  'sitio_id' | 'numero_economico' | 'placas' | 'marca' | 'modelo' | 'color' | 'activo'
>

export function useGuardarUnidad() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, datos }: { id?: number; datos: DatosUnidad }) => {
      const { error } = id
        ? await supabase.from('unidades').update(datos).eq('id', id)
        : await supabase.from('unidades').insert(datos)
      if (error) throw new Error(traducirError(error))
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['unidades'] })
      void queryClient.invalidateQueries({ queryKey: ['conductores'] })
    },
  })
}

// ── Errores de la base → mensajes para el admin ─────────────────────

const DUPLICADOS: Record<string, string> = {
  unidades_placas_key: 'Ya hay una unidad con esas placas',
  unidades_sitio_id_numero_economico_key: 'Ese número económico ya existe en el sitio',
  sitios_nombre_key: 'Ya existe un sitio con ese nombre',
}

function traducirError(error: { code?: string; message: string }): string {
  if (error.code === '23505') {
    const restriccion = Object.keys(DUPLICADOS).find((r) => error.message.includes(r))
    if (restriccion) return DUPLICADOS[restriccion]
  }
  if (error.code === '23514' && error.message.includes('telefono_mx')) {
    return 'El teléfono debe tener 10 dígitos'
  }
  return mensajeDeError(error)
}
