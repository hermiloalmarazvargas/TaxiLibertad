import { QueryClient } from '@tanstack/react-query'

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Los cambios en vivo llegan por Realtime; esto es solo el respaldo.
      staleTime: 30_000,
      retry: 1,
    },
  },
})
