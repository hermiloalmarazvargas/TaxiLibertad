// Prueba en navegador (Chrome) del panel contra Supabase LOCAL.
// Requisitos: `npm run dev` corriendo, las cuentas de prueba creadas
// (ver e2e/README.md) y VITE_MAPTILER_KEY en .env.local. Uso: npm run e2e
//
// El despacho trabaja en el navegador; el conductor y un pasajero actúan
// "desde sus teléfonos" (clientes de Supabase aparte) y todo debe verse en vivo.
import { chromium } from 'playwright-core';
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const URL = 'http://localhost:5173';
const sql = (q) =>
  execFileSync('docker', ['exec', 'supabase_db_taxi-miahuatlan', 'psql', '-U', 'postgres', '-tAc', q]).toString().trim();
const ok = (m) => console.log('  ✔ ' + m);
const cliente = () =>
  createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

const TEL_LLAMADA = '+529516660010';
const TEL_FALSO = '+529516660011';
const limpiar = () => {
  sql(`delete from viajes where contacto_telefono in ('${TEL_LLAMADA}', '${TEL_FALSO}')
       or pasajero_id in (select id from perfiles where telefono = '+529516660012')
       or origen_referencia = 'Prueba sin conductor'`);
  sql(`delete from telefonos_bloqueados where telefono = '${TEL_FALSO}'`);
  sql("delete from auth.users where id in (select id from perfiles where telefono = '+529516660012')");
  sql("update conductor_estado set estado = 'fuera_de_servicio', unidad_id = null, ubicacion = null where conductor_id = (select id from perfiles where usuario = 'chofer.prueba')");
};
limpiar();

// El conductor de prueba se pone disponible cerca del centro.
const chofer = cliente();
assert.ifError((await chofer.auth.signInWithPassword({ email: 'chofer.prueba@usuarios.taxi.internal', password: 'clave1234' })).error);
const choferId = sql("select id from perfiles where usuario = 'chofer.prueba'");
const reportarUbicacion = () =>
  chofer.from('conductor_estado').update({ ubicacion: 'SRID=4326;POINT(-96.5962 16.3292)' }).eq('conductor_id', choferId);

const browser = await chromium.launch({ channel: 'chrome' });
const page = await (await browser.newContext({ viewport: { width: 1500, height: 1000 } })).newPage();
const errores = [];
page.on('pageerror', (e) => errores.push(e.message));
const tarjetaDe = (texto) => page.locator('[data-prueba^="viaje-"]').filter({ hasText: texto });

async function clicEnMapa(lat, lng) {
  const caja = await page.locator('.leaflet-container').boundingBox();
  const p = await page.evaluate(([la, ln]) => window.__mapa.latLngToContainerPoint([la, ln]), [lat, lng]);
  await page.mouse.click(caja.x + p.x, caja.y + p.y);
}

try {
  await page.goto(URL + '/login');
  await page.getByLabel('Usuario').fill('despacho');
  await page.getByLabel('Contraseña').fill('clave1234');
  await page.getByRole('button', { name: 'Entrar' }).click();
  await page.getByRole('heading', { name: 'Viajes', exact: true }).waitFor();
  await page.locator('[data-prueba="conexion"]').getByText('En vivo').waitFor();
  ok('la pantalla de despacho abre con la conexión "En vivo"');

  // ── Taxi disponible en vivo ──
  const antes = await page.locator('[data-prueba="taxis-disponibles"]').innerText();
  assert.ifError((await chofer.rpc('cambiar_disponibilidad', { p_estado: 'disponible', p_unidad_id: Number(sql("select id from unidades where placas = 'TAX0001'")) })).error);
  assert.ifError((await reportarUbicacion()).error);
  await page.waitForFunction(
    (a) => document.querySelector('[data-prueba="taxis-disponibles"]')?.textContent !== a, antes);
  await page.locator('.leaflet-tooltip').filter({ hasText: /^01$/ }).waitFor();
  ok('el taxi que se pone disponible aparece en el mapa (Unidad 01) sin recargar');

  // ── Viaje por teléfono con asignación automática ──
  await page.getByRole('button', { name: 'Nuevo viaje por teléfono' }).click();
  await page.getByLabel('Nombre').fill('Doña Rosa');
  await page.getByLabel('Teléfono').fill('951 666 0010');
  await clicEnMapa(16.329, -96.596); // modo "origen" activo al abrir
  await page.getByText('✓ Marcado').waitFor();
  await page.getByLabel('Referencia', { exact: true }).fill('Frente a la iglesia');
  await page.getByRole('button', { name: 'Marcar destino' }).click();
  await clicEnMapa(16.34, -96.596);
  const { data: estimada } = await chofer.rpc('tarifa_estimada', {
    origen_lat: 16.329, origen_lng: -96.596, destino_lat: 16.34, destino_lng: -96.596,
  });
  const pesos = (n) => new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(n);
  await page.locator('[data-prueba="tarifa-estimada"]').getByText(`Tarifa: ${pesos(Number(estimada[0].monto))}`).waitFor();
  ok(`marca origen y destino en el mapa y muestra la tarifa estimada (${pesos(Number(estimada[0].monto))})`);
  const opciones = await page.getByLabel('Taxi').locator('option').allInnerTexts();
  assert.ok(opciones.some((o) => o.includes('Unidad 01') && o.includes('Chofer Prueba')), opciones.join(' | '));
  ok('lista el taxi disponible con su distancia');

  await page.getByRole('button', { name: 'Crear viaje' }).click();
  await tarjetaDe('Doña Rosa').waitFor();
  await tarjetaDe('Doña Rosa').getByText('Ofrecido a Chofer Prueba').waitFor({ timeout: 10000 });
  assert.equal(sql(`select count(*) from viajes where contacto_telefono = '${TEL_LLAMADA}'`), '1');
  ok('crea el viaje y se ve en vivo a quién se le está ofreciendo');

  // ── El conductor rechaza → el despacho lo asigna a mano ──
  const [oferta] = (await chofer.rpc('mi_oferta_pendiente')).data;
  assert.ifError((await chofer.rpc('responder_oferta', { p_oferta_id: oferta.oferta_id, p_aceptar: false })).error);
  await tarjetaDe('Doña Rosa').getByText('Esperando un taxi disponible').waitFor({ timeout: 10000 });
  ok('al rechazar, la tarjeta lo refleja en vivo');
  await tarjetaDe('Doña Rosa').getByRole('button', { name: 'Asignar taxi' }).click();
  await page.getByRole('dialog').getByText('Unidad 01 · Chofer Prueba').waitFor();
  await page.getByRole('dialog').getByRole('button', { name: 'Asignar', exact: true }).click();
  await tarjetaDe('Doña Rosa').getByText('Taxi en camino').waitFor();
  assert.match(await tarjetaDe('Doña Rosa').innerText(), /Chofer Prueba · Unidad 01/);
  ok('asigna el taxi directamente; la tarjeta muestra conductor y unidad');

  // ── El conductor avanza desde su teléfono ──
  const viajeId = sql(`select id from viajes where contacto_telefono = '${TEL_LLAMADA}'`);
  assert.ifError((await chofer.rpc('avanzar_viaje', { p_viaje_id: viajeId, p_estado: 'conductor_llego' })).error);
  await tarjetaDe('Doña Rosa').getByText('El taxi llegó').waitFor({ timeout: 10000 });
  assert.ifError((await chofer.rpc('avanzar_viaje', { p_viaje_id: viajeId, p_estado: 'en_curso' })).error);
  await tarjetaDe('Doña Rosa').getByText('En viaje').waitFor({ timeout: 10000 });
  await page.screenshot({ path: 'e2e/capturas/viajes.png' });
  assert.ifError((await chofer.rpc('avanzar_viaje', { p_viaje_id: viajeId, p_estado: 'completado' })).error);
  await tarjetaDe('Doña Rosa').waitFor({ state: 'detached', timeout: 10000 });
  ok('"Llegué", "Inicié" y "Terminé" del conductor se ven en vivo; al terminar sale de la lista');

  // ── Un pasajero pide desde la app ──
  const pasajero = cliente();
  assert.ifError((await pasajero.auth.signInAnonymously()).error);
  assert.ifError((await pasajero.rpc('registrar_pasajero', { p_nombre: 'Pasajero App', p_telefono: '9516660012' })).error);
  assert.ifError((await pasajero.auth.refreshSession()).error);
  assert.ifError((await reportarUbicacion()).error);
  assert.ifError((await pasajero.rpc('solicitar_viaje', {
    p_client_request_id: randomUUID(), p_origen_lat: 16.3295, p_origen_lng: -96.5955, p_origen_referencia: 'Tienda azul',
  })).error);
  await tarjetaDe('Pasajero App').waitFor({ timeout: 10000 });
  assert.match(await tarjetaDe('Pasajero App').innerText(), /📱/);
  ok('un viaje pedido desde la app aparece solo, marcado como de la app');

  // ── Llamada falsa: cancelar y bloquear en un paso ──
  await page.getByRole('button', { name: 'Nuevo viaje por teléfono' }).click();
  await page.getByLabel('Nombre').fill('Bromista');
  await page.getByLabel('Teléfono').fill('9516660011');
  await clicEnMapa(16.327, -96.597);
  await page.getByLabel('Taxi').selectOption({ index: 0 });
  await page.getByRole('button', { name: 'Crear viaje' }).click();
  await tarjetaDe('Bromista').waitFor();
  await tarjetaDe('Bromista').getByRole('button', { name: 'Cancelar viaje' }).click();
  await page.getByRole('dialog').getByLabel('Motivo (opcional)').fill('Llamada falsa');
  await page.getByRole('dialog').getByLabel(/Bloquear el número/).check();
  await page.getByRole('dialog').getByRole('button', { name: 'Cancelar viaje' }).click();
  await tarjetaDe('Bromista').waitFor({ state: 'detached' });
  assert.equal(sql(`select motivo from telefonos_bloqueados where telefono = '${TEL_FALSO}'`), 'Llamada falsa');
  ok('cancela una llamada falsa y bloquea el número en el mismo paso');

  await page.getByRole('button', { name: 'Nuevo viaje por teléfono' }).click();
  await page.getByLabel('Nombre').fill('Bromista');
  await page.getByLabel('Teléfono').fill('951 666 0011');
  await clicEnMapa(16.327, -96.597);
  await page.getByRole('button', { name: 'Crear viaje' }).click();
  await page.getByRole('alert').filter({ hasText: 'bloqueado' }).waitFor();
  await page.getByRole('button', { name: 'Cancelar', exact: true }).click();
  ok('un número bloqueado ya no puede recibir viajes por teléfono');

  // ── Sin conductor ──
  sql(`insert into viajes (canal, contacto_nombre, contacto_telefono, origen, origen_referencia, estado)
       values ('telefono', 'Sin Taxi', '${TEL_LLAMADA}', public.punto(16.33, -96.6), 'Prueba sin conductor', 'sin_conductor')`);
  await page.getByRole('alert').filter({ hasText: 'Sin conductor (1)' }).waitFor({ timeout: 10000 });
  assert.match(await page.title(), /\(1\) ¡Sin conductor!/);
  ok('un viaje "sin conductor" aparece arriba en rojo y avisa en la pestaña del navegador');

  await page.screenshot({ path: 'e2e/capturas/viajes-alerta.png' });
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
