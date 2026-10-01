# Taxi Miahuatlán

App de taxis para Miahuatlán, Oaxaca: app del conductor, app del pasajero (Flutter)
y panel de despacho (React), sobre Supabase.

## Estructura

```
supabase/   migraciones SQL, funciones Edge, pruebas pgTAP, seed
panel/      panel web de despacho (fase 2)
apps/       conductor/ y pasajero/ en Flutter (fases 3 y 4)
packages/   taxi_core: código Dart compartido
docs/       decisiones y guías de prueba
```

## Base de datos local

Requisitos: Node 18+, Docker Desktop (con WSL 2 en Windows).

```bash
npm install          # instala el CLI de Supabase del proyecto
npm run db:start     # levanta Postgres, Auth, Realtime, Studio (la 1.ª vez descarga imágenes)
npm run db:reset     # recrea la base: aplica migraciones + seed.sql
npm run test:db      # corre las pruebas de supabase/tests
npm run db:stop
```

Si cambias `supabase/config.toml`, reinicia con `npm run db:stop && npm run db:start`.

## Cuentas

Copia `.env.example` a `.env` y llénalo con los valores de `npx supabase status`.

```bash
# Personal (conductor, despachador, admin): lo crea el admin
npm run usuario:crear -- --rol admin --usuario admin --nombre "Administrador"
npm run usuario:crear -- --rol conductor --usuario juan.perez --nombre "Juan Pérez" --sitio "Sitio Centro"

# Prueba de punta a punta del inicio de sesión (solo local)
npm run probar:auth
```

Los pasajeros no tienen cuenta con contraseña: entran de forma anónima y se
registran con nombre y teléfono (`registrar_pasajero`).

Studio local: http://127.0.0.1:54323
