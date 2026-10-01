import type { InputHTMLAttributes, ReactNode, SelectHTMLAttributes } from 'react'

const ESTILO_CONTROL = 'mt-1 block min-h-12 w-full rounded-lg border border-slate-300 bg-white px-3 text-lg'

type Etiqueta = { etiqueta: string; ayuda?: ReactNode }

export function Campo({ etiqueta, ayuda, ...props }: Etiqueta & InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="block">
      <span className="font-medium">{etiqueta}</span>
      <input className={ESTILO_CONTROL} {...props} />
      {ayuda && <span className="mt-1 block text-sm text-slate-500">{ayuda}</span>}
    </label>
  )
}

export function Selector({ etiqueta, ayuda, children, ...props }: Etiqueta & SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <label className="block">
      <span className="font-medium">{etiqueta}</span>
      <select className={ESTILO_CONTROL} {...props}>
        {children}
      </select>
      {ayuda && <span className="mt-1 block text-sm text-slate-500">{ayuda}</span>}
    </label>
  )
}
