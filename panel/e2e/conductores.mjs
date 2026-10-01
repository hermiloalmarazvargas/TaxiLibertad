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
const correo = (u) => `${u}@usuarios.taxi.internal`;
const sql = (q) =>
  execFileSync('docker', ['exec', 'supabase_db_taxi-miahuatlan', 'psql', '-U', 'postgres', '-tAc', q]).toString().trim();
const cliente = () => createClient(API, KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const ok = (m) => console.log('  ✔ ' + m);

// Limpia restos de una corrida anterior.
sql("delete from auth.users where email = 'maria.jose@usuarios.taxi.internal'");

const browser = await chromium.launch({ channel: 'chrome' });
const ctx = await browser.newContext({
  viewport: { width: 1280, height: 900 },
  permissions: ['clipboard-read', 'clipboard-write'],
});
const page = await ctx.newPage();
const errores = [];
page.on('pageerror', (e) => errores.push(e.message));

async function entrar(usuario) {
  await page.goto(URL + '/login');
  await page.getByLabel('Usuario').fill(usuario);
  await page.getByLabel('Contraseña').fill('clave1234');
  await page.getByRole('button', { name: 'Entrar' }).click();
  await page.getByRole('heading', { name: 'Viajes' }).waitFor();
}
const fila = (u) => page.locator(`[data-prueba="conductor-${u}"]`);

try {
  console.log('Admin');
  await entrar('admin');
  await page.getByRole('link', { name: 'Conductores' }).click();
  await fila('chofer.prueba').waitFor();
  ok('la lista muestra al conductor existente');

  // ── Alta ──
  await page.getByRole('button', { name: 'Dar de alta' }).click();
  await page.getByLabel('Nombre completo').fill('María José Ruiz');
  assert.equal(await page.getByLabel('Usuario para iniciar sesión').inputValue(), 'maria.jose');
  ok('sugiere el usuario a partir del nombre, sin acentos');
  await page.getByLabel('Teléfono (opcional)').fill('951 222 3344');
  await page.getByRole('dialog').getByRole('button', { name: 'Dar de alta' }).click();
  await page.getByRole('heading', { name: 'Conductor dado de alta' }).waitFor();
  const password = await page.locator('[data-prueba="password"]').innerText();
  assert.match(password, /^[a-z\d]{10}$/);
  await page.screenshot({ path: 'e2e/capturas/alta-password.png' });
  await page.getByRole('button', { name: 'Copiar' }).click();
  assert.match(await page.evaluate(() => navigator.clipboard.readText()), /Usuario: maria\.jose\r?\nContraseña: /);
  await page.getByRole('button', { name: 'Listo' }).click();
  await fila('maria.jose').waitFor();
  assert.match(await fila('maria.jose').innerText(), /951 222 3344/);
  assert.match(await fila('maria.jose').innerText(), /Fuera de servicio/);
  ok('da de alta, muestra la contraseña una vez, la copia y la agrega a la lista');

  const chofer = cliente();
  const { data: sesion, error: e1 } = await chofer.auth.signInWithPassword({ email: correo('maria.jose'), password });
  assert.ifError(e1);
  ok('el conductor nuevo inicia sesión con esa contraseña');

  // ── Duplicado ──
  await page.getByRole('button', { name: 'Dar de alta' }).click();
  await page.getByLabel('Nombre completo').fill('María José Otra');
  await page.getByRole('dialog').getByRole('button', { name: 'Dar de alta' }).click();
  await page.getByRole('dialog').getByRole('alert').waitFor();
  assert.match(await page.getByRole('dialog').getByRole('alert').innerText(), /"maria\.jose" ya existe/);
  await page.getByRole('button', { name: 'Cancelar' }).click();
  ok('usuario repetido muestra el error dentro del formulario');

  // ── En vivo ──
  const unidad = Number(sql("select id from unidades where placas = 'TAX0003'"));
  const r1 = await chofer.rpc('cambiar_disponibilidad', { p_estado: 'disponible', p_unidad_id: unidad });
  assert.ifError(r1.error);
  await chofer
    .from('conductor_estado')
    .update({ ubicacion: 'SRID=4326;POINT(-96.596 16.329)' })
    .eq('conductor_id', sesion.user.id);
  await fila('maria.jose').getByText('Disponible', { exact: true }).waitFor({ timeout: 10000 });
  assert.match(await fila('maria.jose').innerText(), /Unidad 03/);
  ok('se pone disponible y la tabla cambia sola (Realtime), con su unidad');

  sql(
    `update conductor_estado set estado = 'fuera_de_servicio', motivo_fuera = 'sin_respuesta', unidad_id = null where conductor_id = '${sesion.user.id}'`,
  );
  await fila('maria.jose').getByText('Fuera: no respondió ofertas').waitFor({ timeout: 10000 });
  ok('"Fuera: no respondió ofertas" aparece en vivo');
  await page.screenshot({ path: 'e2e/capturas/conductores-admin.png' });

  // ── Nueva contraseña ──
  await fila('maria.jose').getByRole('button', { name: 'Nueva contraseña' }).click();
  await page.getByRole('button', { name: 'Generar contraseña' }).click();
  await page.getByRole('heading', { name: 'Contraseña restablecida' }).waitFor();
  const nueva = await page.locator('[data-prueba="password"]').innerText();
  assert.notEqual(nueva, password);
  await page.getByRole('button', { name: 'Listo' }).click();
  assert.ifError((await cliente().auth.signInWithPassword({ email: correo('maria.jose'), password: nueva })).error);
  assert.ok((await cliente().auth.signInWithPassword({ email: correo('maria.jose'), password })).error);
  ok('restablece la contraseña: la nueva sirve y la anterior no');

  // ── Desactivar / reactivar ──
  await fila('maria.jose').getByRole('button', { name: 'Desactivar' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Desactivar' }).click();
  await fila('maria.jose').getByText('Cuenta desactivada').waitFor();
  assert.ok((await cliente().auth.signInWithPassword({ email: correo('maria.jose'), password: nueva })).error);
  ok('desactiva: la fila lo indica y ya no puede iniciar sesión');
  await fila('maria.jose').getByRole('button', { name: 'Reactivar' }).click();
  await page.getByRole('dialog').getByRole('button', { name: 'Reactivar' }).click();
  await fila('maria.jose').getByRole('button', { name: 'Desactivar' }).waitFor();
  assert.ifError((await cliente().auth.signInWithPassword({ email: correo('maria.jose'), password: nueva })).error);
  ok('reactiva: puede volver a iniciar sesión');

  await page.getByPlaceholder('Buscar por nombre, usuario o unidad').fill('maría');
  assert.equal(await page.locator('tbody tr').count(), 1);
  await page.getByPlaceholder('Buscar por nombre, usuario o unidad').fill('');
  ok('la búsqueda filtra por nombre');

  console.log('Despachador');
  await page.getByRole('button', { name: 'Cerrar sesión' }).click();
  await entrar('despacho');
  await page.getByRole('link', { name: 'Conductores' }).click();
  await fila('maria.jose').waitFor();
  assert.equal(await page.getByRole('button', { name: 'Dar de alta' }).count(), 0);
  assert.equal(await page.getByRole('button', { name: 'Desactivar' }).count(), 0);
  assert.equal(await page.getByRole('columnheader', { name: 'Acciones' }).count(), 0);
  ok('ve la lista y los estados, sin botones de administración');

  await page.setViewportSize({ width: 390, height: 800 });
  assert.ok((await page.evaluate(() => document.documentElement.scrollWidth)) <= 390);
  ok('en ancho de teléfono la página no se desborda (la tabla se desplaza dentro de su caja)');

  assert.deepEqual(errores, []);
  ok('sin errores de JavaScript');
  console.log('\nTodo bien ✔');
} catch (e) {
  await page.screenshot({ path: 'e2e/capturas/fallo.png' });
  console.error('\n✘ Falló:', e.message);
  process.exitCode = 1;
} finally {
  await browser.close();
  sql("delete from auth.users where email = 'maria.jose@usuarios.taxi.internal'");
}
