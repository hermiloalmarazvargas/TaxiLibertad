// Prueba en navegador (Chrome) del panel contra Supabase LOCAL.
// Requisitos: `npm run dev` corriendo y las cuentas de prueba creadas
// (ver e2e/README.md). Uso: npm run e2e
import { chromium } from 'playwright-core';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const URL = 'http://localhost:5173';
const API = process.env.VITE_SUPABASE_URL;
const KEY = process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const sql = (q) =>
  execFileSync('docker', ['exec', 'supabase_db_taxi-miahuatlan', 'psql', '-U', 'postgres', '-tAc', q]).toString().trim();
const ok = (m) => console.log('  ✔ ' + m);
const limpiar = () => {
  sql("delete from unidades where placas = 'TAX-0021'");
  sql("delete from sitios where nombre = 'Sitio Mercado'");
};
limpiar();

const browser = await chromium.launch({ channel: 'chrome' });
const page = await (await browser.newContext({ viewport: { width: 1280, height: 900 } })).newPage();
const errores = [];
page.on('pageerror', (e) => errores.push(e.message));
const dialogo = () => page.getByRole('dialog');
const sitio = (n) => page.locator(`[data-prueba="sitio-${n}"]`);
const unidad = (p) => page.locator(`[data-prueba="unidad-${p}"]`);
const chofer = createClient(API, KEY, { auth: { persistSession: false, autoRefreshToken: false } });

try {
  await page.goto(URL + '/login');
  await page.getByLabel('Usuario').fill('admin');
  await page.getByLabel('Contraseña').fill('clave1234');
  await page.getByRole('button', { name: 'Entrar' }).click();
  await page.getByRole('link', { name: 'Unidades y sitios' }).click();
  await sitio('Sitio Centro').getByText('3 unidad(es) activa(s)', { exact: false }).waitFor();
  ok('muestra los sitios con su número de unidades activas');

  // ── Sitios ──
  await page.getByRole('button', { name: 'Agregar sitio' }).click();
  await dialogo().getByLabel('Nombre del sitio').fill('Sitio Mercado');
  await dialogo().getByLabel('Teléfono del sitio (opcional)').fill('123');
  await dialogo().getByRole('button', { name: 'Guardar' }).click();
  assert.match(await dialogo().getByRole('alert').innerText(), /10 dígitos/);
  await dialogo().getByLabel('Teléfono del sitio (opcional)').fill('(951) 555-1234');
  await dialogo().getByRole('button', { name: 'Guardar' }).click();
  await sitio('Sitio Mercado').waitFor();
  assert.match(await sitio('Sitio Mercado').innerText(), /951 555 1234/);
  ok('agrega un sitio; valida y normaliza el teléfono');

  await page.getByRole('button', { name: 'Agregar sitio' }).click();
  await dialogo().getByLabel('Nombre del sitio').fill('Sitio Mercado');
  await dialogo().getByRole('button', { name: 'Guardar' }).click();
  assert.match(await dialogo().getByRole('alert').innerText(), /Ya existe un sitio con ese nombre/);
  await dialogo().getByRole('button', { name: 'Cancelar' }).click();
  ok('nombre de sitio repetido muestra un mensaje claro');

  // ── Unidades ──
  await page.getByRole('button', { name: 'Agregar unidad' }).click();
  await dialogo().getByLabel('Sitio').selectOption({ label: 'Sitio Mercado' });
  await dialogo().getByLabel('Número económico').fill('21');
  await dialogo().getByLabel('Placas').fill('tax-0021');
  await dialogo().getByLabel('Marca').fill('Nissan');
  await dialogo().getByRole('button', { name: 'Guardar' }).click();
  await unidad('TAX-0021').waitFor();
  assert.match(await sitio('Sitio Mercado').innerText(), /1 unidad\(es\) activa\(s\)/);
  ok('agrega una unidad (placas en mayúsculas) y el sitio la cuenta');

  await page.getByRole('button', { name: 'Agregar unidad' }).click();
  await dialogo().getByLabel('Sitio').selectOption({ label: 'Sitio Mercado' });
  await dialogo().getByLabel('Número económico').fill('22');
  await dialogo().getByLabel('Placas').fill('TAX-0021');
  await dialogo().getByRole('button', { name: 'Guardar' }).click();
  assert.match(await dialogo().getByRole('alert').innerText(), /Ya hay una unidad con esas placas/);
  await dialogo().getByRole('button', { name: 'Cancelar' }).click();
  ok('placas repetidas muestran un mensaje claro');

  await unidad('TAX-0021').getByRole('button', { name: 'Editar' }).click();
  await dialogo().getByLabel('Color').fill('Blanco con rojo');
  await dialogo().getByRole('button', { name: 'Guardar' }).click();
  await unidad('TAX-0021').getByText('Nissan · Blanco con rojo').waitFor();
  ok('edita una unidad');

  // ── En servicio ──
  const { error: e1 } = await chofer.auth.signInWithPassword({
    email: 'chofer.prueba@usuarios.taxi.internal', password: 'clave1234',
  });
  assert.ifError(e1);
  const tax1 = Number(sql("select id from unidades where placas = 'TAX0001'"));
  assert.ifError((await chofer.rpc('cambiar_disponibilidad', { p_estado: 'disponible', p_unidad_id: tax1 })).error);
  await page.reload();
  await unidad('TAX0001').getByText('En servicio').waitFor();
  assert.match(await unidad('TAX0001').innerText(), /Chofer Prueba/);
  ok('muestra qué conductor trae la unidad en servicio');
  await unidad('TAX0001').getByRole('button', { name: 'Desactivar' }).click();
  await unidad('TAX0001').getByRole('alert').waitFor();
  assert.match(await unidad('TAX0001').getByRole('alert').innerText(), /está en servicio/);
  ok('no deja desactivar una unidad en servicio y explica por qué');
  assert.ifError((await chofer.rpc('cambiar_disponibilidad', { p_estado: 'fuera_de_servicio' })).error);

  await sitio('Sitio Centro').getByRole('button', { name: 'Desactivar' }).click();
  await page.getByRole('alert').filter({ hasText: 'unidades o conductores activos' }).waitFor();
  ok('no deja desactivar un sitio con unidades o conductores activos');

  // ── Filtros ──
  await unidad('TAX-0021').getByRole('button', { name: 'Desactivar' }).click();
  await unidad('TAX-0021').waitFor({ state: 'detached' });
  await page.getByLabel('Mostrar inactivas').check();
  await unidad('TAX-0021').getByText('Inactiva').waitFor();
  ok('una unidad desactivada se oculta; se ve con "Mostrar inactivas"');
  await page.getByRole('combobox', { name: 'Sitio' }).selectOption({ label: 'Sitio Mercado' });
  assert.equal(await page.locator('tbody tr').count(), 1);
  ok('el filtro por sitio funciona');

  // ── El sitio nuevo aparece en el alta de conductores ──
  await page.getByRole('link', { name: 'Conductores' }).click();
  await page.getByRole('button', { name: 'Dar de alta' }).click();
  const opciones = await dialogo().getByLabel('Sitio').locator('option').allInnerTexts();
  assert.ok(opciones.includes('Sitio Mercado'), opciones.join(','));
  ok('el sitio nuevo aparece al dar de alta conductores');
  await dialogo().getByRole('button', { name: 'Cancelar' }).click();

  await page.goto(URL + '/unidades');
  await sitio('Sitio Mercado').waitFor();
  await page.screenshot({ path: 'e2e/capturas/unidades.png', fullPage: true });
  assert.deepEqual(errores, []);
  ok('sin errores de JavaScript');
  console.log('\nTodo bien ✔');
} catch (e) {
  await page.screenshot({ path: 'e2e/capturas/fallo.png' });
  console.error('\n✘ Falló:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
  await chofer.rpc('cambiar_disponibilidad', { p_estado: 'fuera_de_servicio' });
  limpiar();
}
