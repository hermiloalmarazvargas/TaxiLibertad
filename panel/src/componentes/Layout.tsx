import { NavLink, Outlet } from 'react-router'
import { useSesion, type Rol } from '../auth/sesion'
import { Boton } from './Boton'

type Seccion = { ruta: string; titulo: string; roles: Rol[] }

const SECCIONES: Seccion[] = [
  { ruta: '/', titulo: 'Viajes', roles: ['despachador', 'admin'] },
  { ruta: '/conductores', titulo: 'Conductores', roles: ['despachador', 'admin'] },
  { ruta: '/unidades', titulo: 'Unidades y sitios', roles: ['admin'] },
  { ruta: '/zonas', titulo: 'Zonas y tarifas', roles: ['admin'] },
  { ruta: '/bloqueos', titulo: 'Números bloqueados', roles: ['despachador', 'admin'] },
  { ruta: '/reportes', titulo: 'Reportes', roles: ['despachador', 'admin'] },
]

const NOMBRE_ROL: Record<Rol, string> = {
  admin: 'Administrador',
  despachador: 'Despacho',
  conductor: 'Conductor',
  pasajero: 'Pasajero',
}

export function Layout() {
  const { usuario, cerrarSesion } = useSesion()
  if (!usuario) return null

  const visibles = SECCIONES.filter((s) => s.roles.includes(usuario.rol))

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <aside className="flex flex-col gap-4 bg-slate-900 p-4 text-white md:w-60">
        <div>
          <p className="text-lg font-bold">Taxi Miahuatlán</p>
          <p className="text-sm text-slate-300">
            {usuario.nombre} · {NOMBRE_ROL[usuario.rol]}
          </p>
        </div>

        <nav className="flex gap-1 overflow-x-auto md:flex-col">
          {visibles.map((s) => (
            <NavLink
              key={s.ruta}
              to={s.ruta}
              end={s.ruta === '/'}
              className={({ isActive }) =>
                `whitespace-nowrap rounded-lg px-3 py-3 font-medium ${
                  isActive ? 'bg-amber-500 text-slate-950' : 'text-slate-200 hover:bg-slate-800'
                }`
              }
            >
              {s.titulo}
            </NavLink>
          ))}
        </nav>

        <Boton variante="secundario" className="mt-auto" onClick={() => void cerrarSesion()}>
          Cerrar sesión
        </Boton>
      </aside>

      <main className="flex-1 p-4 md:p-8">
        <Outlet />
      </main>
    </div>
  )
}
