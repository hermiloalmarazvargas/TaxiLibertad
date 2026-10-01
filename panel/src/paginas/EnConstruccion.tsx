// Marcador para secciones que se construyen en los siguientes pasos.
export function EnConstruccion({ titulo, descripcion }: { titulo: string; descripcion: string }) {
  return (
    <section>
      <h1 className="text-2xl font-bold">{titulo}</h1>
      <p className="mt-2 max-w-prose text-slate-600">{descripcion}</p>
    </section>
  )
}
