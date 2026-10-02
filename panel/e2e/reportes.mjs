// Prueba en navegador (Chrome) del panel contra Supabase LOCAL.
// Requisitos: `npm run dev` corriendo y las cuentas de prueba creadas
// (ver e2e/README.md). Uso: npm run e2e
import { chromium } from 'playwright-core';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const URL = 'http://localhost:5173';
const sql = (q) =>
  execFileSync('docker', ['exec', 'supabase_db_taxi-miahuatlan', 'psql', '-U', 'postgres', '-tAc', q]).toString().trim();
const ok = (m) => console.log('  ✔ ' + m);
const pesos = (n) => new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(n);
const hoy = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Mexico_City' }).format(new Date());
const ayer = (() => {
  const d = new Date(`${hoy}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
})();

// Viajes de prueba: hoy y ayer (hora local), con el conductor de prueba.
const PREFIJO = '00000000-0000-0000-0000-0000000e2e0';
const limpiar = () => sql(`delete from viajes where id::text like '${PREFIJO}%'`);
limpiar();
const chofer = sql("select id from perfiles where usuario = 'chofer.prueba'");
const unidad = sql("select id from unidades where placas = 'TAX0002'");
sql(`insert into viajes (id, canal, origen, estado, conductor_id, unidad_id, tarifa_monto, solicitado_en, asignado_en) values
  ('${PREFIJO}1', 'telefono', public.punto(16.33,-96.6), 'completado', '${chofer}', ${unidad}, 45, '${hoy} 09:00-06', '${hoy} 09:04-06'),
  ('${PREFIJO}2', 'app', public.punto(16.33,-96.6), 'completado', '${chofer}', ${unidad}, null, '${hoy} 10:00-06', '${hoy} 10:02-06'),
  ('${PREFIJO}3', 'app', public.punto(16.33,-96.6), 'sin_conductor', null, null, null, '${ayer} 22:00-06', null)`);

// Lo que debe mostrar la tabla = lo que devuelve la RPC para el mismo usuario.
const despacho = createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
assert.ifError((await despacho.auth.signInWithPassword({ email: 'despacho@usuarios.taxi.internal', password: 'clave1234' })).error);

const browser = await chromium.launch({ channel: 'chrome' });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 }, acceptDownloads: true });
const page = await ctx.newPage();
const errores = [];
page.on('pageerror', (e) => errores.push(e.message));

try {
  await page.goto(URL + '/login');
  await page.getByLabel('Usuario').fill('despacho');
  await page.getByLabel('Contraseña').fill('clave1234');
  await page.getByRole('button', { name: 'Entrar' }).click();
  await page.getByRole('link', { name: 'Reportes' }).click();
  await page.locator('[data-prueba="reporte-dia"]').waitFor();
  assert.equal(await page.getByRole('button', { name: 'Últimos 7 días' }).getAttribute('aria-pressed'), 'true');
  assert.equal(await page.locator('[data-prueba="reporte-dia"] tbody tr').count(), 7);
  ok('por omisión muestra los últimos 7 días, un renglón por día');

  await page.getByRole('button', { name: 'Hoy' }).click();
  await page.locator('[data-prueba="reporte-dia"] tbody tr').first().getByText(/./).first().waitFor();
  await page.waitForFunction(() => document.querySelectorAll('[data-prueba="reporte-dia"] tbody tr').length === 1);
  const { data: dia } = await despacho.rpc('reporte_por_dia', { p_desde: hoy, p_hasta: hoy });
  const total = await page.locator('[data-prueba="total-dia"]').innerText();
  assert.match(total, new RegExp(`Total\\s+${dia[0].solicitados}\\s+${dia[0].completados}`));
  assert.ok(total.includes(pesos(Number(dia[0].ingresos))), `${total} vs ${dia[0].ingresos}`);
  assert.ok(dia[0].completados >= 2 && Number(dia[0].ingresos) >= 45 && dia[0].a_convenir >= 1);
  ok('"Hoy" coincide con la base, incluidos los viajes de prueba');

  await page.getByRole('button', { name: 'Ayer' }).click();
  await page.waitForFunction(
    (sel) => document.querySelector(sel)?.textContent?.includes('Total'),
    '[data-prueba="total-dia"]',
  );
  const { data: diaAyer } = await despacho.rpc('reporte_por_dia', { p_desde: ayer, p_hasta: ayer });
  assert.ok(diaAyer[0].sin_conductor >= 1, 'el viaje de las 10 p. m. de ayer cuenta ayer');
  ok('un viaje de las 10 p. m. cuenta en el día local correcto');

  await page.getByRole('button', { name: 'Hoy' }).click();
  const conductorFila = page.locator('[data-prueba="reporte-conductor"] tbody tr').filter({ hasText: 'Chofer Prueba' });
  await conductorFila.waitFor();
  const { data: porConductor } = await despacho.rpc('reporte_por_conductor', { p_desde: hoy, p_hasta: hoy });
  const esperado = porConductor.find((f) => f.nombre === 'Chofer Prueba');
  assert.match(await conductorFila.innerText(), new RegExp(`Chofer Prueba[\\s\\S]*\\s${esperado.completados}\\s`));
  ok('el reporte por conductor coincide con la base');

  const [descarga] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name: 'Descargar CSV' }).first().click(),
  ]);
  assert.equal(descarga.suggestedFilename(), `viajes-por-dia_${hoy}_${hoy}.csv`);
  const csv = readFileSync(await descarga.path(), 'utf8');
  assert.ok(csv.startsWith('﻿Fecha,Solicitados,Completados'), 'CSV con BOM y encabezados');
  assert.ok(csv.includes(`${hoy},${dia[0].solicitados},${dia[0].completados}`));
  ok('descarga el CSV con acentos compatibles con Excel');

  await page.getByLabel('Desde').fill(hoy);
  await page.getByLabel('Hasta').fill(ayer);
  await page.getByRole('alert').filter({ hasText: 'rango de fechas válido' }).waitFor();
  ok('un rango invertido muestra un aviso en lugar de consultar');

  await page.getByRole('button', { name: 'Últimos 7 días' }).click();
  await page.locator('[data-prueba="reporte-dia"]').waitFor();
  await page.screenshot({ path: 'e2e/capturas/reportes.png', fullPage: true });
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
