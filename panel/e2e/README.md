# Pruebas del panel en navegador

Recorren el panel en Chrome (con `playwright-core`) contra Supabase local.

Requisitos, una sola vez (desde la raíz del proyecto):

```bash
npm run usuario:crear -- --rol admin --usuario admin --nombre "Administrador" --password clave1234
npm run usuario:crear -- --rol despachador --usuario despacho --nombre "Despacho Central" --password clave1234
npm run usuario:crear -- --rol conductor --usuario chofer.prueba --nombre "Chofer Prueba" --sitio "Sitio Centro" --password clave1234
```

Luego, con `npm run dev` corriendo en otra terminal:

```bash
cd panel
npm run e2e
```

Las capturas quedan en `e2e/capturas/` (no se suben a git).
