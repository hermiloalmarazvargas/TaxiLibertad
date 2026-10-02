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

# Prueba de punta a punta de un viaje: Realtime + cron de 20 s (~30 s, solo local)
npm run probar:viaje
```

## Panel de despacho

```bash
cd panel
cp .env.example .env.local   # llénalo con los valores de `npx supabase status`
npm install
npm run dev                  # http://localhost:5173
```

Si cambia el esquema de la base: `npm run gen:tipos` (desde la raíz) regenera
`panel/src/types/database.ts`.

```bash
# Pruebas de las Edge Functions de alta y restablecer contraseña (solo local)
npm run probar:alta

# Pruebas del panel en Chrome (requiere `npm run dev`; ver panel/e2e/README.md)
cd panel && npm run e2e
```

## Apps (Flutter)

```
packages/taxi_core/   código compartido (sesión, errores, conexión, tema, mapa)
apps/conductor/       app del conductor
apps/pasajero/        app del pasajero
```

Configuración (una vez por app): copia `config/local.example.json` como
`config/local.json` (no se sube a git) y pon la `PUBLISHABLE_KEY` de
`npx supabase status` y la key de MapTiler **para apps** (no la del panel:
esa está restringida al dominio web y las apps no mandan ese origen).

Correr en un teléfono Android conectado por USB, contra Supabase local:

```bash
# El teléfono ve tu Supabase local como 127.0.0.1:54321 (repetir cada vez que se reconecte el cable)
adb reverse tcp:54321 tcp:54321

cd apps/conductor   # o apps/pasajero
flutter run --dart-define-from-file=config/local.json
```

Pruebas: `flutter test` y `flutter analyze` dentro de `packages/taxi_core`, `apps/conductor` y `apps/pasajero`.

Para probar la app del conductor sin la del pasajero (desde la raíz):

```bash
# Un pasajero simulado pide un taxi cerca del taxi disponible; muestra en vivo
# lo que pasa con el viaje. Ctrl+C lo cancela.
npm run simular:pasajero
npm run simular:pasajero -- --destino-lat 16.34 --destino-lng -96.596 --referencia "Portón verde"
```

Los pasajeros no tienen cuenta con contraseña: entran de forma anónima y se
registran con nombre y teléfono (`registrar_pasajero`).

Studio local: http://127.0.0.1:54323
