import { QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router'
import { RutaProtegida } from './auth/RutaProtegida'
import { SesionProvider } from './auth/SesionProvider'
import { Layout } from './componentes/Layout'
import { ConductoresPagina } from './features/conductores/ConductoresPagina'
import { UnidadesPagina } from './features/unidades/UnidadesPagina'
import { queryClient } from './lib/consultas'
import { EnConstruccion } from './paginas/EnConstruccion'
import { Login } from './paginas/Login'

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <SesionProvider>
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route
              element={
                <RutaProtegida>
                  <Layout />
                </RutaProtegida>
              }
            >
              <Route
                index
                element={<EnConstruccion titulo="Viajes" descripcion="Mapa con viajes en curso y alta de viajes por teléfono." />}
              />
              <Route
                path="reportes"
                element={<EnConstruccion titulo="Reportes" descripcion="Viajes por día y por conductor." />}
              />
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
                    <EnConstruccion titulo="Zonas y tarifas" descripcion="Dibujar zonas en el mapa y tarifas entre zonas." />
                  </RutaProtegida>
                }
              />
            </Route>
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </BrowserRouter>
      </SesionProvider>
    </QueryClientProvider>
  )
}
