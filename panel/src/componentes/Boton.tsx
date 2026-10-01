import type { ButtonHTMLAttributes } from 'react'

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  variante?: 'primario' | 'secundario' | 'peligro'
}

const ESTILOS = {
  primario: 'bg-amber-500 text-slate-950 hover:bg-amber-400 focus-visible:outline-amber-600',
  secundario: 'bg-white text-slate-900 ring-1 ring-slate-300 hover:bg-slate-50 focus-visible:outline-slate-500',
  peligro: 'bg-red-600 text-white hover:bg-red-500 focus-visible:outline-red-700',
}

// Botones grandes y de alto contraste.
export function Boton({ variante = 'primario', className = '', ...props }: Props) {
  return (
    <button
      className={`inline-flex min-h-12 items-center justify-center rounded-lg px-5 text-base font-semibold
        focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-50
        ${ESTILOS[variante]} ${className}`}
      {...props}
    />
  )
}
