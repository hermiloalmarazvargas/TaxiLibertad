import { useEffect, useState } from 'react'

// Hora actual que se refresca sola, para textos como "hace 3 min" o
// "sin señal" que cambian aunque no lleguen eventos nuevos.
export function useAhora(cadaMs: number) {
  const [ahora, setAhora] = useState(() => Date.now())
  useEffect(() => {
    const id = setInterval(() => setAhora(Date.now()), cadaMs)
    return () => clearInterval(id)
  }, [cadaMs])
  return ahora
}
