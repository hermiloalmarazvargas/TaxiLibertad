// Prueba en navegador (Chrome) del panel contra Supabase LOCAL.
// Requisitos: `npm run dev` corriendo y las cuentas de prueba creadas
// (ver e2e/README.md). Uso: npm run e2e
import { chromium } from 'playwright-core';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';

const URL = 'http://localhost:5173';
const sql = (q) =>
  execFileSync('docker', ['exec', 'supabase_db_taxi-miahuatlan', 'psql', '-U', 'postgres', '-tAc', q]).toString().trim();
const ok = (m) => console.log('  ✔ ' + m);
const TEL = '+529517778888';
const limpiar = () => {
  sql(`delete from telefonos_bloqueados where telefono = '${TEL}'`);
  sql(`delete from auth.users where id in (select id from perfiles where telefono = '${TEL}')`);
};
limpiar();

// Un pasajero registrado con ese número, para ver su nombre en la lista.
const pasajero = createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
assert.ifError((await pasajero.auth.signInAnonymously()).error);
assert.ifError((await pasajero.rpc('registrar_pasajero', { p_nombre: 'Pasajero Bromista', p_telefono: '951 777 8888' })).error);
// Igual que la app: renovar la sesión para que el token traiga rol=pasajero.
assert.ifError((await pasajero.auth.refreshSession()).error);

const browser = await chromium.launch({ channel: 'chrome' });
const page = await (await browser.newContext({ viewport: { width: 1280, height: 900 } })).newPage();
const errores = [];
page.on('pageerror', (e) => errores.push(e.message));
const fila = () => page.locator(`[data-prueba="bloqueo-${TEL}"]`);

try {
  await page.goto(URL + '/login');
  await page.getByLabel('Usuario').fill('despacho');
  await page.getByLabel('Contraseña').fill('clave1234');
  await page.getByRole('button', { name: 'Entrar' }).click();
  await page.getByRole('link', { name: 'Números bloqueados' }).click();
  await page.getByRole('heading', { name: 'Números bloqueados' }).waitFor();
  ok('el despacho entra a Números bloqueados');

  await page.getByLabel('Teléfono').fill('951 777');
  await page.getByLabel('Motivo').fill('Pedidos falsos');
  await page.getByRole('button', { name: 'Bloquear número' }).click();
  assert.match(await page.getByRole('alert').innerText(), /10 dígitos/);
  ok('valida que el teléfono tenga 10 dígitos');

  await page.getByLabel('Teléfono').fill('(951) 777-8888');
  await page.getByRole('button', { name: 'Bloquear número' }).click();
  await fila().waitFor();
  const texto = await fila().innerText();
  assert.match(texto, /951 777 8888/);
  assert.match(texto, /Pasajero registrado: Pasajero Bromista/);
  assert.match(texto, /Pedidos falsos/);
  assert.match(texto, /por Despacho Central/);
  assert.equal(await page.getByLabel('Teléfono').inputValue(), '', 'el formulario se limpia');
  ok('bloquea: muestra número, pasajero registrado, motivo y quién lo bloqueó');

  // El bloqueo aplica de inmediato aunque el pasajero tenga sesión abierta.
  const { error } = await pasajero.rpc('solicitar_viaje', {
    p_client_request_id: crypto.randomUUID(), p_origen_lat: 16.329, p_origen_lng: -96.596,
  });
  assert.equal(error?.hint, 'telefono_bloqueado');
  ok('el pasajero bloqueado ya no puede pedir viajes');

  await page.getByLabel('Teléfono').fill('9517778888');
  await page.getByLabel('Motivo').fill('Otra vez');
  await page.getByRole('button', { name: 'Bloquear número' }).click();
  await page.getByRole('alert').filter({ hasText: 'ya está bloqueado' }).waitFor();
  ok('bloquear dos veces el mismo número muestra un mensaje claro');

  await page.getByLabel('Buscar número bloqueado').fill('777 88');
  assert.equal(await page.locator('[data-prueba^="bloqueo-"]').count(), 1);
  await page.getByLabel('Buscar número bloqueado').fill('');
  ok('la búsqueda encuentra el número aunque se escriba con espacios');

  await page.screenshot({ path: 'e2e/capturas/bloqueos.png' });
  await fila().getByRole('button', { name: 'Desbloquear' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Desbloquear' }).click();
  await fila().waitFor({ state: 'detached' });
  ok('desbloquea el número');

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
