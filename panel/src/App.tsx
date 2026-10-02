import { QueryClientProvider } from '@tanstack/react-query'
import { lazy, Suspense } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router'
import { RutaProtegida } from './auth/RutaProtegida'
import { SesionProvider } from './auth/SesionProvider'
import { Layout } from './componentes/Layout'
import { BloqueosPagina } from './features/bloqueos/BloqueosPagina'
import { ConductoresPagina } from './features/conductores/ConductoresPagina'
import { ReportesPagina } from './features/reportes/ReportesPagina'
import { UnidadesPagina } from './features/unidades/UnidadesPagina'
import { queryClient } from './lib/consultas'
import { Login } from './paginas/Login'
import { Cargando } from './componentes/Cargando'

// Las páginas con mapa (Leaflet) se cargan aparte: el inicio de sesión no las
// necesita y así carga rápido aunque la señal sea mala.
const ViajesPagina = lazy(() => import('./features/viajes/ViajesPagina').then((m) => ({ default: m.ViajesPagina })))
const ZonasPagina = lazy(() => import('./features/zonas/ZonasPagina').then((m) => ({ default: m.ZonasPagina })))

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <SesionProvider>
        <BrowserRouter>
          <Suspense fallback={<Cargando />}>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route
              element={
                <RutaProtegida>
                  <Layout />
                </RutaProtegida>
              }
            >
              <Route index element={<ViajesPagina />} />
              <Route path="reportes" element={<ReportesPagina />} />
              <Route path="bloqueos" element={<BloqueosPagina />} />
              {/* El despacho la ve en modo lectura; las acciones son solo del admin. */}
              <Route path="conductores" element={<ConductoresPagina />} />
              <Route
                path="unidades"
                element={
                  <RutaProtegida roles={['admin']}>
                    <UnidadesPagina />
                  </RutaProtegida>
                }
              />
              <Route
                path="zonas"
                element={
                  <RutaProtegida roles={['admin']}>
                    <ZonasPagina />
                  </RutaProtegida>
                }
              />
            </Route>
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
          </Suspense>
        </BrowserRouter>
      </SesionProvider>
    </QueryClientProvider>
  )
}
