import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useRef, useState } from 'react'
import { mensajeDeError } from '../../lib/errores'
import { supabase } from '../../lib/supabase'
import type { Database } from '../../types/database'

type Tablas = Database['public']['Tables']
export type EstadoViaje = Database['public']['Enums']['estado_viaje']

// Viajes que el despacho debe atender. "sin_conductor" se muestra hasta
// 12 h después para que nadie se quede sin respuesta.
export const ESTADOS_ACTIVOS: EstadoViaje[] = ['sin_conductor', 'buscando', 'asignado', 'conductor_llego', 'en_curso']
const HORAS_VISIBLES = 12

// ── Viajes ──────────────────────────────────────────────────────────

const CONSULTA_VIAJES = `
  id, estado, canal, solicitado_en, asignado_en, llego_en, iniciado_en,
  origen_lat, origen_lng, origen_referencia, destino_lat, destino_lng, destino_referencia,
  tarifa_monto, tarifa_recargo, contacto_nombre, contacto_telefono,
  zona_origen:zonas!viajes_zona_origen_id_fkey ( nombre ),
  zona_destino:zonas!viajes_zona_destino_id_fkey ( nombre ),
  pasajero:perfiles!viajes_pasajero_id_fkey ( nombre, telefono ),
  conductor:conductores ( perfil:perfiles ( nombre ) ),
  unidad:unidades ( numero_economico ),
  ofertas:ofertas_viaje ( conductor_id, respuesta, expira_en )
` as const

async function cargarViajes() {
  const desde = new Date(Date.now() - HORAS_VISIBLES * 3_600_000).toISOString()
  const { data, error } = await supabase
    .from('viajes')
    .select(CONSULTA_VIAJES)
    .in('estado', ESTADOS_ACTIVOS)
    .gte('solicitado_en', desde)
    .order('solicitado_en')
  if (error) throw error
  return data
}

export type Viaje = Awaited<ReturnType<typeof cargarViajes>>[number]

export function useViajesActivos() {
  return useQuery({ queryKey: ['viajes', 'activos'], queryFn: cargarViajes })
}

// Nombre y teléfono de quien pidió el viaje (por app o por teléfono).
export function contactoDe(v: Viaje): { nombre: string; telefono: string | null } {
  return v.canal === 'telefono'
    ? { nombre: v.contacto_nombre ?? 'Sin nombre', telefono: v.contacto_telefono }
    : { nombre: v.pasajero?.nombre ?? 'Pasajero', telefono: v.pasajero?.telefono ?? null }
}

// ── Taxis en servicio ───────────────────────────────────────────────

const CONSULTA_TAXIS = `
  conductor_id, estado, lat, lng, ubicacion_en, unidad_id,
  unidad:unidades ( numero_economico ),
  conductor:conductores ( perfil:perfiles ( nombre ) )
` as const

async function cargarTaxis() {
  const { data, error } = await supabase
    .from('conductor_estado')
    .select(CONSULTA_TAXIS)
    .neq('estado', 'fuera_de_servicio')
  if (error) throw error
  return data
}

export type Taxi = Awaited<ReturnType<typeof cargarTaxis>>[number]

export function useTaxis() {
  return useQuery({ queryKey: ['taxis'], queryFn: cargarTaxis })
}

// Igual que el servidor: sin ubicación reciente no recibe ofertas automáticas.
export const SEGUNDOS_UBICACION_VIGENTE = 60
export const tieneSenal = (t: Taxi, ahora: number) =>
  !!t.ubicacion_en && ahora - new Date(t.ubicacion_en).getTime() <= SEGUNDOS_UBICACION_VIGENTE * 1000

// ── En vivo ─────────────────────────────────────────────────────────

type FilaEstado = Tablas['conductor_estado']['Row']

// Una sola suscripción para la pantalla de despacho:
//  · viajes y ofertas → recargar la lista (agrupando ráfagas de eventos)
//  · ubicación de taxis (cada pocos segundos) → actualizar solo la caché
// Devuelve si la conexión en vivo está activa. Al reconectar se recarga
// todo, por si se perdieron eventos mientras no había señal.
export function useDespachoEnVivo(): boolean {
  const queryClient = useQueryClient()
  const [conectado, setConectado] = useState(false)
  const temporizador = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    const recargarViajes = () => {
      if (temporizador.current) clearTimeout(temporizador.current)
      temporizador.current = setTimeout(
        () => void queryClient.invalidateQueries({ queryKey: ['viajes'] }),
        250,
      )
    }

    const canal = supabase
      .channel('panel-despacho')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'viajes' }, recargarViajes)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'ofertas_viaje' }, recargarViajes)
      .on<FilaEstado>('postgres_changes', { event: '*', schema: 'public', table: 'conductor_estado' }, ({ new: nuevo }) => {
        if (!nuevo || !('conductor_id' in nuevo)) return
        const taxis = queryClient.getQueryData<Taxi[]>(['taxis'])
        const actual = taxis?.find((t) => t.conductor_id === nuevo.conductor_id)
        // Cambió de estado o de unidad (o apareció): recargar para traer nombre y unidad.
        if (!actual || actual.estado !== nuevo.estado || actual.unidad_id !== nuevo.unidad_id) {
          void queryClient.invalidateQueries({ queryKey: ['taxis'] })
          return
        }
        queryClient.setQueryData<Taxi[]>(['taxis'], (previa) =>
          previa?.map((t) =>
            t.conductor_id === nuevo.conductor_id
              ? { ...t, lat: nuevo.lat, lng: nuevo.lng, ubicacion_en: nuevo.ubicacion_en }
              : t,
          ),
        )
      })
      .subscribe((estado) => {
        const ok = estado === 'SUBSCRIBED'
        setConectado(ok)
        if (ok) {
          void queryClient.invalidateQueries({ queryKey: ['viajes'] })
          void queryClient.invalidateQueries({ queryKey: ['taxis'] })
        }
      })

    return () => {
      if (temporizador.current) clearTimeout(temporizador.current)
      void supabase.removeChannel(canal)
    }
  }, [queryClient])

  return conectado
}

// ── Acciones ────────────────────────────────────────────────────────

export type Punto = { lat: number; lng: number }

export function useTarifaEstimada(origen: Punto | null, destino: Punto | null) {
  return useQuery({
    queryKey: ['tarifa', origen, destino],
    enabled: !!origen,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('tarifa_estimada', {
        origen_lat: origen!.lat,
        origen_lng: origen!.lng,
        destino_lat: destino?.lat,
        destino_lng: destino?.lng,
      })
      if (error) throw error
      return data[0]
    },
  })
}

export type DatosViajeTelefonico = {
  clientRequestId: string
  nombre: string
  telefono: string
  origen: Punto
  origenReferencia: string
  destino: Punto | null
  destinoReferencia: string
  conductorId: string | null
}

export function useCrearViajeTelefonico() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (d: DatosViajeTelefonico) => {
      const { data, error } = await supabase.rpc('crear_viaje_telefonico', {
        // Mismo id en cada reintento: si se manda dos veces, no se duplica el viaje.
        p_client_request_id: d.clientRequestId,
        p_contacto_nombre: d.nombre,
        p_contacto_telefono: d.telefono,
        p_origen_lat: d.origen.lat,
        p_origen_lng: d.origen.lng,
        p_origen_referencia: d.origenReferencia || undefined,
        p_destino_lat: d.destino?.lat,
        p_destino_lng: d.destino?.lng,
        p_destino_referencia: d.destinoReferencia || undefined,
        p_conductor_id: d.conductorId ?? undefined,
      })
      if (error) throw new Error(mensajeDeError(error))
      return data
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['viajes'] }),
  })
}

export function useAsignarViaje() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ viajeId, conductorId }: { viajeId: string; conductorId: string }) => {
      const { error } = await supabase.rpc('asignar_viaje', { p_viaje_id: viajeId, p_conductor_id: conductorId })
      if (error) throw new Error(mensajeDeError(error))
    },
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: ['viajes'] })
      void queryClient.invalidateQueries({ queryKey: ['taxis'] })
    },
  })
}

export function useCancelarViaje() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ viajeId, motivo }: { viajeId: string; motivo: string }) => {
      const { error } = await supabase.rpc('cancelar_viaje', { p_viaje_id: viajeId, p_motivo: motivo || undefined })
      if (error) throw new Error(mensajeDeError(error))
    },
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: ['viajes'] })
      void queryClient.invalidateQueries({ queryKey: ['taxis'] })
    },
  })
}
