// Prueba en navegador (Chrome) del panel contra Supabase LOCAL.
// Requisitos: `npm run dev` corriendo y las cuentas de prueba creadas
// (ver e2e/README.md). Uso: npm run e2e
import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';
const URL = 'http://localhost:5173';
const browser = await chromium.launch({ channel: 'chrome' });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const page = await ctx.newPage();
const errores = [];
page.on('console', (m) => { if (m.type() === 'error') errores.push(m.text()); });
page.on('pageerror', (e) => errores.push(e.message));

async function entrar(usuario, password) {
  await page.goto(URL + '/login');
  await page.getByLabel('Usuario').fill(usuario);
  await page.getByLabel('Contraseña').fill(password);
  await page.getByRole('button', { name: 'Entrar' }).click();
}
const ok = (m) => console.log('  ✔ ' + m);

await page.goto(URL + '/conductores');
await page.waitForURL('**/login');
ok('sin sesión redirige a /login');

await entrar('admin', 'mala1234');
await page.getByRole('alert').waitFor();
assert.equal(await page.getByRole('alert').innerText(), 'Usuario o contraseña incorrectos');
ok('contraseña incorrecta muestra mensaje en español');

await entrar('chofer.prueba', 'clave1234');
await page.getByRole('alert').waitFor();
assert.match(await page.getByRole('alert').innerText(), /no tiene acceso al panel/);
ok('un conductor no puede entrar al panel');

// Vuelve a la página que se pidió al inicio sin sesión (/conductores).
await entrar('despacho', 'clave1234');
await page.getByRole('button', { name: 'Cerrar sesión' }).waitFor();
assert.equal(new globalThis.URL(page.url()).pathname, '/conductores');
ok('tras iniciar sesión vuelve a la página que se había pedido');
const navDesp = await page.locator('nav a').allInnerTexts();
assert.deepEqual(navDesp, ['Viajes', 'Conductores', 'Reportes']);
ok('despachador ve Viajes, Conductores y Reportes');
await page.goto(URL + '/zonas');
await page.getByRole('heading', { name: 'Viajes' }).waitFor();
assert.equal(new globalThis.URL(page.url()).pathname, '/');
ok('despachador que fuerza /zonas regresa al inicio');
await page.getByRole('button', { name: 'Cerrar sesión' }).click();
await page.waitForURL('**/login');
ok('cerrar sesión regresa al login');

await entrar('admin', 'clave1234');
await page.getByRole('heading', { name: 'Viajes' }).waitFor();
assert.deepEqual(await page.locator('nav a').allInnerTexts(), ['Viajes', 'Conductores', 'Unidades y sitios', 'Zonas y tarifas', 'Reportes']);
assert.match(await page.locator('aside').innerText(), /Administrador · Administrador/);
ok('admin ve las 5 secciones y su nombre');
await page.reload();
await page.getByRole('heading', { name: 'Viajes' }).waitFor();
ok('al recargar la página la sesión se conserva');
await page.getByRole('link', { name: 'Zonas y tarifas' }).click();
await page.getByRole('heading', { name: 'Zonas y tarifas' }).waitFor();
await page.screenshot({ path: 'e2e/capturas/panel-admin.png' });
await page.setViewportSize({ width: 390, height: 800 });
await page.screenshot({ path: 'e2e/capturas/panel-movil.png' });
const anchoScroll = await page.evaluate(() => document.documentElement.scrollWidth);
assert.ok(anchoScroll <= 390, 'sin scroll horizontal en móvil: ' + anchoScroll);
ok('en ancho de teléfono no hay scroll horizontal');

const relevantes = errores.filter((e) => !/400 \(Bad Request\)/.test(e));
assert.deepEqual(relevantes, [], 'errores en consola');
ok('sin errores de JavaScript en la consola');
await browser.close();
console.log('\nTodo bien ✔');
