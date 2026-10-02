// Prueba en navegador (Chrome) del panel contra Supabase LOCAL.
// Requisitos: `npm run dev` corriendo, las cuentas de prueba creadas
// (ver e2e/README.md) y VITE_MAPTILER_KEY en .env.local. Uso: npm run e2e
import { chromium } from 'playwright-core';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const URL = 'http://localhost:5173';
const sql = (q) =>
  execFileSync('docker', ['exec', 'supabase_db_taxi-miahuatlan', 'psql', '-U', 'postgres', '-tAc', q]).toString().trim();
const ok = (m) => console.log('  ✔ ' + m);

const limpiar = () => {
  sql("update configuracion set recargo_nocturno_pct = 10, recargo_desde = '22:00', recargo_hasta = '06:00'");
  sql("delete from zonas where nombre in ('Zona Este', 'Zona Oriente')");
  sql(`update tarifas set monto = 60 where zona_origen_id = (select id from zonas where nombre = 'Norte')
       and zona_destino_id = (select id from zonas where nombre = 'Sur')`);
  sql(`insert into tarifas (zona_origen_id, zona_destino_id, monto)
       select id, id, 35 from zonas where nombre = 'Centro' on conflict do nothing`);
};
limpiar();

const admin = createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
assert.ifError((await admin.auth.signInWithPassword({ email: 'admin@usuarios.taxi.internal', password: 'clave1234' })).error);
const zonaEn = async (lat, lng) => (await admin.rpc('tarifa_estimada', { origen_lat: lat, origen_lng: lng })).data[0];

const browser = await chromium.launch({ channel: 'chrome' });
const page = await (await browser.newContext({ viewport: { width: 1400, height: 1000 } })).newPage();
const errores = [];
page.on('pageerror', (e) => errores.push(e.message));
const zona = (n) => page.locator(`[data-prueba="zona-${n}"]`);

// Convierte lat/lng a píxeles de la página usando el mapa de Leaflet.
async function clicEn(lat, lng) {
  const caja = await page.locator('.leaflet-container').boundingBox();
  const p = await page.evaluate(([la, ln]) => window.__mapa.latLngToContainerPoint([la, ln]), [lat, lng]);
  await page.mouse.click(caja.x + p.x, caja.y + p.y);
}

try {
  await page.goto(URL + '/login');
  await page.getByLabel('Usuario').fill('admin');
  await page.getByLabel('Contraseña').fill('clave1234');
  await page.getByRole('button', { name: 'Entrar' }).click();
  await page.getByRole('link', { name: 'Zonas y tarifas' }).click();
  await zona('Centro').waitFor();

  // ── Mapa de MapTiler ──
  await page.waitForFunction(() =>
    [...document.querySelectorAll('img.leaflet-tile')].some((i) => i.src.includes('streets-v2') && i.complete && i.naturalWidth > 0),
  );
  ok('el mapa de MapTiler carga');
  await page.locator('.leaflet-control-layers').hover();
  await page.locator('.leaflet-control-layers').getByText('Satélite', { exact: true }).click();
  await page.waitForFunction(() =>
    [...document.querySelectorAll('img.leaflet-tile')].some((i) => i.src.includes('hybrid') && i.complete && i.naturalWidth > 0),
  );
  await page.screenshot({ path: 'e2e/capturas/zonas-satelite.png' });
  ok('cambia a vista satelital');
  await page.locator('.leaflet-control-layers').hover();
  await page.locator('.leaflet-control-layers').getByText('Mapa', { exact: true }).click();

  // ── Dibujar una zona en el hueco al este del Centro ──
  assert.equal((await zonaEn(16.329, -96.588)).zona_origen_id, null, 'antes, ese punto no tiene zona');
  await page.getByRole('button', { name: 'Dibujar zona nueva' }).click();
  await page.getByText('Haz clic en el mapa para marcar cada esquina').waitFor();
  const esquinas = [[16.326, -96.591], [16.326, -96.585], [16.332, -96.585], [16.332, -96.591]];
  for (const [la, ln] of esquinas) await clicEn(la, ln);
  await clicEn(...esquinas[0]); // cerrar en el primer punto
  await page.getByRole('heading', { name: 'Zona nueva' }).waitFor();
  await page.getByLabel('Nombre de la zona').fill('Zona Este');
  await page.getByRole('button', { name: 'Color #9333ea' }).click();
  await page.getByRole('button', { name: 'Guardar zona' }).click();
  await zona('Zona Este').waitFor();
  assert.equal((await zonaEn(16.329, -96.588)).zona_origen, 'Zona Este');
  ok('dibuja una zona con clics en el mapa y la base ya la usa para tarifas');

  // ── Editar la forma arrastrando una esquina hacia el este ──
  const areaAntes = Number(sql("select st_area(poligono::geography) from zonas where nombre = 'Zona Este'"));
  await zona('Zona Este').getByRole('button', { name: 'Editar forma' }).click();
  await page.getByText('Arrastra los puntos').waitFor();
  // Esperar a que termine la animación de acercamiento a la zona.
  await page.waitForTimeout(800);
  // Se usa el marcador real: al dibujar, Geoman pega las esquinas al borde de
  // zonas vecinas (snapping), así que pueden no estar donde se hizo clic.
  let vertice = null;
  for (const m of await page.locator('.marker-icon:not(.marker-icon-middle)').all()) {
    const bb = await m.boundingBox();
    const c = { x: bb.x + bb.width / 2, y: bb.y + bb.height / 2 };
    if (!vertice || c.x - c.y > vertice.x - vertice.y) vertice = c; // esquina superior derecha
  }
  await page.mouse.move(vertice.x, vertice.y);
  await page.mouse.down();
  // Leaflet reconoce el arrastre solo después de un primer movimiento pequeño.
  await page.mouse.move(vertice.x + 5, vertice.y - 5);
  await page.mouse.move(vertice.x + 60, vertice.y - 40, { steps: 20 });
  await page.mouse.up();
  await page.screenshot({ path: 'e2e/capturas/zona-editada.png' });
  await page.getByRole('button', { name: 'Guardar forma' }).click();
  await page.getByRole('button', { name: 'Dibujar zona nueva' }).waitFor();
  const areaDespues = Number(sql("select st_area(poligono::geography) from zonas where nombre = 'Zona Este'"));
  assert.ok(areaDespues > areaAntes * 1.05, `el área debió crecer: ${areaAntes} → ${areaDespues}`);
  ok('edita la forma arrastrando una esquina');

  // ── Nombre y color ──
  await zona('Zona Este').getByRole('button', { name: 'Nombre y color' }).click();
  await page.getByLabel('Nombre de la zona').fill('Zona Oriente');
  await page.getByRole('button', { name: 'Guardar zona' }).click();
  await zona('Zona Oriente').waitFor();
  ok('cambia el nombre de la zona');

  await zona('Zona Oriente').getByRole('button', { name: 'Nombre y color' }).click();
  await page.getByLabel('Nombre de la zona').fill('Centro');
  await page.getByRole('button', { name: 'Guardar zona' }).click();
  await page.getByRole('dialog').getByRole('alert').filter({ hasText: 'Ya existe una zona con ese nombre' }).waitFor();
  await page.getByRole('button', { name: 'Cancelar' }).click();
  ok('no permite repetir el nombre de otra zona');

  // ── Desactivar ──
  await zona('Zona Oriente').getByRole('button', { name: 'Desactivar' }).click();
  await zona('Zona Oriente').getByText('Inactiva').waitFor();
  assert.equal((await zonaEn(16.329, -96.588)).zona_origen_id, null);
  await zona('Zona Oriente').getByRole('button', { name: 'Activar' }).click();
  await zona('Zona Oriente').getByRole('button', { name: 'Desactivar' }).waitFor();
  ok('una zona desactivada deja de usarse para tarifas');

  // ── Tarifas ──
  await page.getByRole('tab', { name: 'Tarifas' }).click();
  const celda = (o, d) => page.getByLabel(`Tarifa de ${o} a ${d}`);
  await celda('Centro', 'Zona Oriente').waitFor();
  assert.equal(await celda('Centro', 'Norte').inputValue(), '45');
  assert.equal(await celda('Centro', 'Zona Oriente').inputValue(), '');
  ok('la tabla muestra las tarifas guardadas y "a convenir" vacío');

  await celda('Centro', 'Zona Oriente').fill('50');
  assert.equal(await celda('Zona Oriente', 'Centro').inputValue(), '50');
  await page.getByRole('button', { name: 'Guardar cambios (2)' }).click();
  await page.getByText('Tarifas guardadas ✓').waitFor();
  const { data: tarifa } = await admin.rpc('tarifa_estimada', {
    origen_lat: 16.329, origen_lng: -96.596, destino_lat: 16.329, destino_lng: -96.588,
  });
  assert.equal(Number(tarifa[0].monto_base), 50); // sin recargo nocturno: la prueba no depende de la hora
  assert.equal(
    sql(`select count(*) from tarifas t join zonas z on z.id = t.zona_destino_id
         where z.nombre = 'Zona Oriente' and t.actualizado_por = (select id from perfiles where usuario = 'admin')`),
    '1',
  );
  ok('captura A→B, se aplica también B→A y la base calcula $50 (registra quién la cambió)');

  await page.getByLabel('Aplicar el mismo precio de regreso').uncheck();
  await celda('Norte', 'Sur').fill('70');
  assert.equal(await celda('Sur', 'Norte').inputValue(), '60');
  await celda('Centro', 'Centro').fill('');
  await page.getByRole('button', { name: 'Guardar cambios (2)' }).click();
  await page.getByText('Tarifas guardadas ✓').waitFor();
  assert.equal(sql(`select monto from tarifas where zona_origen_id = (select id from zonas where nombre='Norte')
                    and zona_destino_id = (select id from zonas where nombre='Sur')`), '70.00');
  assert.equal(sql(`select monto from tarifas where zona_origen_id = (select id from zonas where nombre='Sur')
                    and zona_destino_id = (select id from zonas where nombre='Norte')`), '60.00');
  assert.equal((await zonaEn(16.329, -96.596)).zona_origen, 'Centro');
  const { data: centro } = await admin.rpc('tarifa_estimada', {
    origen_lat: 16.329, origen_lng: -96.596, destino_lat: 16.33, destino_lng: -96.597,
  });
  assert.equal(centro[0].monto_base, null);
  ok('sin "mismo regreso" solo cambia una dirección; vaciar una casilla la deja "a convenir"');

  await celda('Centro', 'Norte').fill('abc');
  await page.getByRole('button', { name: /Guardar cambios/ }).click();
  await page.getByRole('alert').filter({ hasText: 'Revisa los montos' }).waitFor();
  await page.getByRole('button', { name: 'Descartar' }).click();
  assert.equal(await celda('Centro', 'Norte').inputValue(), '45');
  ok('un monto inválido no se guarda; "Descartar" regresa a lo guardado');

  // ── Recargo nocturno ──
  const ejemplo = page.locator('[data-prueba="ejemplo-recargo"]');
  assert.ok(
    (await ejemplo.innerText()).includes('$45.00 pedido entre las 22:00 y las 06:00 cuesta $50.00 (+$5.00)'),
    await ejemplo.innerText(),
  );
  ok('muestra el recargo actual con un ejemplo (10 %: $45 → $50)');
  await page.getByLabel('Porcentaje').fill('150');
  assert.match(await ejemplo.innerText(), /entre 0 y 100/);
  assert.ok(await page.getByRole('button', { name: 'Guardar recargo' }).isDisabled());
  await page.getByLabel('Porcentaje').fill('20');
  await page.getByLabel('Desde').fill('01:00');
  await page.getByLabel('Hasta').fill('05:00');
  await page.getByRole('button', { name: 'Guardar recargo' }).click();
  await page.getByText('Recargo guardado ✓').waitFor();
  const { data: noche } = await admin.rpc('tarifa_estimada', {
    origen_lat: 16.329, origen_lng: -96.596, destino_lat: 16.34, destino_lng: -96.596,
    momento: new Date().toISOString().slice(0, 10) + 'T03:00:00-06:00',
  });
  assert.equal(Number(noche[0].monto), 54);
  ok('cambia a 20 % de 01:00 a 05:00 y la base cobra $45 + $9 a las 3 a. m.');
  await page.screenshot({ path: 'e2e/capturas/tarifas.png', fullPage: true });

  assert.deepEqual(errores, []);
  ok('sin errores de JavaScript');
  console.log('\nTodo bien ✔');
} catch (e) {
  await page.screenshot({ path: 'e2e/capturas/fallo.png' });
  console.error('\n✘ Falló:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
  limpiar();
}
