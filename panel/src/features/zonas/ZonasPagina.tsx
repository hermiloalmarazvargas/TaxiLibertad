import { useState } from 'react'
import { EditorZonas } from './EditorZonas'
import { RecargoNocturno } from './RecargoNocturno'
import { TablaTarifas } from './TablaTarifas'

type Pestana = 'zonas' | 'tarifas'

export function ZonasPagina() {
  const [pestana, setPestana] = useState<Pestana>('zonas')

  return (
    <section className="space-y-6">
      <h1 className="text-2xl font-bold">Zonas y tarifas</h1>

      <div role="tablist" className="flex gap-2">
        {(['zonas', 'tarifas'] as const).map((p) => (
          <button
            key={p}
            role="tab"
            aria-selected={pestana === p}
            onClick={() => setPestana(p)}
            className={`min-h-12 rounded-lg px-5 font-semibold ${
              pestana === p ? 'bg-slate-900 text-white' : 'bg-white text-slate-900 ring-1 ring-slate-300'
            }`}
          >
            {p === 'zonas' ? 'Zonas en el mapa' : 'Tarifas'}
          </button>
        ))}
      </div>

      {pestana === 'zonas' ? (
        <EditorZonas />
      ) : (
        <div className="space-y-8">
          <TablaTarifas />
          <RecargoNocturno />
        </div>
      )}
    </section>
  )
}
