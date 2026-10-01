import type { ReactNode } from 'react'

export function MensajeError({ children }: { children: ReactNode }) {
  if (!children) return null
  return (
    <p className="rounded-lg bg-red-50 p-3 text-red-800 ring-1 ring-red-200" role="alert">
      {children}
    </p>
  )
}

const COLORES = {
  verde: 'bg-green-100 text-green-900 ring-green-300',
  ambar: 'bg-amber-100 text-amber-900 ring-amber-300',
  rojo: 'bg-red-100 text-red-900 ring-red-300',
  gris: 'bg-slate-100 text-slate-700 ring-slate-300',
  oscuro: 'bg-slate-800 text-white ring-slate-800',
}

export type ColorInsignia = keyof typeof COLORES

export function Insignia({ color, children }: { color: ColorInsignia; children: ReactNode }) {
  return (
    <span className={`inline-block rounded-full px-3 py-1 text-sm font-semibold ring-1 ${COLORES[color]}`}>
      {children}
    </span>
  )
}
