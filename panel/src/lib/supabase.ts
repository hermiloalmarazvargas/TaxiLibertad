import { createClient } from '@supabase/supabase-js'
import type { Database } from '../types/database'

const url = import.meta.env.VITE_SUPABASE_URL
const llave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!url || !llave) {
  throw new Error('Faltan VITE_SUPABASE_URL o VITE_SUPABASE_PUBLISHABLE_KEY (ver panel/.env.example)')
}

// Con la llave publicable: todo pasa por RLS según el usuario que inició sesión.
export const supabase = createClient<Database>(url, llave)
