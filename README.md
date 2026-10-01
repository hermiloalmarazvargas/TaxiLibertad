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
npx supabase test db # corre las pruebas de supabase/tests
npm run db:stop
```

Studio local: http://127.0.0.1:54323
