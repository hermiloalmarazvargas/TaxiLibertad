import { useEffect, useRef, type ReactNode } from 'react'

type Props = {
  abierto: boolean
  titulo: string
  onCerrar: () => void
  // Impide cerrar con Esc (p. ej. cuando se muestra algo que no se puede recuperar).
  soloConBoton?: boolean
  children: ReactNode
}

// Ventana modal con <dialog> nativo: maneja foco, tecla Esc y fondo.
export function Modal({ abierto, titulo, onCerrar, soloConBoton = false, children }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  // El evento "close" también se dispara cuando el padre cierra el modal
  // (abierto → false). Solo hay que avisar al padre si lo cerró el usuario
  // (tecla Esc); si no, se pisaría el siguiente diálogo que el padre abrió.
  const cerradoDesdeFuera = useRef(false)

  useEffect(() => {
    const dialogo = ref.current
    if (!dialogo) return
    if (abierto && !dialogo.open) dialogo.showModal()
    if (!abierto && dialogo.open) {
      cerradoDesdeFuera.current = true
      dialogo.close()
    }
  }, [abierto])

  function alCerrar() {
    if (cerradoDesdeFuera.current) {
      cerradoDesdeFuera.current = false
      return
    }
    onCerrar()
  }

  return (
    <dialog
      ref={ref}
      onClose={alCerrar}
      onCancel={(e) => {
        if (soloConBoton) e.preventDefault()
      }}
      aria-labelledby="titulo-modal"
      className="m-auto w-[min(32rem,calc(100vw-2rem))] rounded-2xl p-0 shadow-xl backdrop:bg-slate-900/50"
    >
      {abierto && (
        <div className="space-y-4 p-6">
          <h2 id="titulo-modal" className="text-xl font-bold">
            {titulo}
          </h2>
          {children}
        </div>
      )}
    </dialog>
  )
}
