import { FunctionsHttpError } from '@supabase/supabase-js'
import { supabase } from './supabase'

// Error de negocio devuelto por una Edge Function: { error, codigo }.
export class ErrorDeFuncion extends Error {
  readonly codigo: string

  constructor(mensaje: string, codigo: string) {
    super(mensaje)
    this.codigo = codigo
  }
}

// Llama a una Edge Function con la sesión actual y devuelve su respuesta.
// Si responde 4xx/5xx, lanza ErrorDeFuncion con el mensaje en español.
export async function invocarFuncion<T>(nombre: string, cuerpo: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke<T>(nombre, { body: cuerpo })
  if (error instanceof FunctionsHttpError) {
    const detalle = (await error.context.json().catch(() => ({}))) as { error?: string; codigo?: string }
    throw new ErrorDeFuncion(detalle.error ?? 'Ocurrió un error inesperado', detalle.codigo ?? 'desconocido')
  }
  if (error) throw error
  return data as T
}
