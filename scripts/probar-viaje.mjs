// Prueba de punta a punta de un viaje contra Supabase LOCAL, con clientes
// reales (como las apps): Realtime, cron de 20 s y transacciones separadas.
// Tarda ~30 s porque espera a que venza una oferta de verdad.
//
// Uso: npm run probar:viaje
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { correoDeUsuario, crearClienteAdmin } from './lib/supabase-admin.mjs';

const url = process.env.SUPABASE_URL;
if (!/127\.0\.0\.1|localhost/.test(url ?? '')) {
  console.error('Este script solo corre contra Supabase local.');
  process.exit(1);
}

const admin = crearClienteAdmin();
const nuevoCliente = () =>
  createClient(url, process.env.SUPABASE_PUBLISHABLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

const ORIGEN = { lat: 16.329, lng: -96.596 };
const sufijo = Date.now().toString(36);
const usuariosCreados = [];
const viajesCreados = [];
const canales = [];

async function paso(nombre, fn) {
  const inicio = Date.now();
  await fn();
  console.log(`  ✔ ${nombre} (${((Date.now() - inicio) / 1000).toFixed(1)} s)`);
}

const ok = ({ data, error }) => {
  if (error) throw new Error(`${error.message}${error.hint ? ` [${error.hint}]` : ''}`);
  return data;
};

// Espera el primer evento de Realtime que cumpla la condición.
function esperarEvento(cliente, tabla, filtro, condicion, segundos) {
  const promesa = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Sin evento de ${tabla} en ${segundos} s`)), segundos * 1000);
    const canal = cliente
      .channel(`prueba-${tabla}-${randomUUID()}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: tabla, filter: filtro }, (payload) => {
        if (condicion(payload.new)) {
          clearTimeout(timer);
          resolve(payload.new);
        }
      });
    canales.push(canal);
    canal.subscribe((status) => {
      if (status === 'SUBSCRIBED') canal.listo = true;
    });
  });
  // Evita "unhandled rejection" si otro paso falla antes de esperar este evento.
  promesa.catch(() => {});
  return promesa;
}

const suscrito = async () => {
  // Dar tiempo a que todas las suscripciones queden activas.
  for (let i = 0; i < 50 && !canales.every((c) => c.listo); i++) {
    await new Promise((r) => setTimeout(r, 100));
  }
  // SUBSCRIBED puede llegar un instante antes de que se entreguen cambios.
  await new Promise((r) => setTimeout(r, 1000));
};

async function crearConductor(nombre, placas) {
  const usuario = `prueba.${nombre}.${sufijo}`;
  const password = 'clave1234';
  const { user } = ok(await admin.auth.admin.createUser({
    email: correoDeUsuario(usuario), password, email_confirm: true, app_metadata: { alta: 'admin' },
  }));
  usuariosCreados.push(user.id);
  const sitio = ok(await admin.from('sitios').select('id').eq('nombre', 'Sitio Centro').single());
  ok(await admin.from('perfiles').insert({ id: user.id, rol: 'conductor', nombre, usuario }));
  ok(await admin.from('conductores').insert({ perfil_id: user.id, sitio_id: sitio.id }));
  const unidad = ok(await admin.from('unidades').select('id').eq('placas', placas).single());

  const cliente = nuevoCliente();
  ok(await cliente.auth.signInWithPassword({ email: correoDeUsuario(usuario), password }));
  return { id: user.id, cliente, unidadId: unidad.id };
}

async function main() {
  console.log('Preparación');
  const c1 = await crearConductor('cercano', 'TAX0001');
  const c2 = await crearConductor('lejano', 'TAX0002');

  await paso('dos conductores disponibles con ubicación', async () => {
    for (const [c, lat] of [[c1, 16.3295], [c2, 16.338]]) {
      ok(await c.cliente.rpc('cambiar_disponibilidad', { p_estado: 'disponible', p_unidad_id: c.unidadId }));
      ok(await c.cliente.from('conductor_estado')
        .update({ ubicacion: `SRID=4326;POINT(${ORIGEN.lng} ${lat})` }).eq('conductor_id', c.id));
    }
  });

  const pasajero = nuevoCliente();
  await paso('pasajero anónimo registrado', async () => {
    const { user } = ok(await pasajero.auth.signInAnonymously());
    usuariosCreados.push(user.id);
    ok(await pasajero.rpc('registrar_pasajero', { p_nombre: 'Pasajera Prueba', p_telefono: '9519991234' }));
    ok(await pasajero.auth.refreshSession());
  });

  console.log('Viaje');
  const ofertaC1 = esperarEvento(c1.cliente, 'ofertas_viaje', `conductor_id=eq.${c1.id}`, () => true, 10);
  const ofertaC2 = esperarEvento(c2.cliente, 'ofertas_viaje', `conductor_id=eq.${c2.id}`, () => true, 40);
  await suscrito();

  const viaje = ok(await pasajero.rpc('solicitar_viaje', {
    p_client_request_id: randomUUID(),
    p_origen_lat: ORIGEN.lat, p_origen_lng: ORIGEN.lng, p_origen_referencia: 'Frente al mercado',
    p_destino_lat: 16.34, p_destino_lng: -96.596,
  }));
  viajesCreados.push(viaje.id);

  await paso('el conductor más cercano recibe la oferta por Realtime', async () => {
    await ofertaC1;
    const [oferta] = ok(await c1.cliente.rpc('mi_oferta_pendiente'));
    assert.equal(oferta.viaje_id, viaje.id);
    assert.equal(oferta.origen_referencia, 'Frente al mercado');
  });

  await paso('c1 no responde: a los ~20 s el cron se la pasa a c2', async () => {
    await ofertaC2;
  });

  const asignado = esperarEvento(pasajero, 'viajes', `id=eq.${viaje.id}`, (v) => v.estado === 'asignado', 10);
  await suscrito();
  await paso('c2 acepta y el pasajero se entera por Realtime', async () => {
    const [oferta] = ok(await c2.cliente.rpc('mi_oferta_pendiente'));
    ok(await c2.cliente.rpc('responder_oferta', { p_oferta_id: oferta.oferta_id, p_aceptar: true }));
    await asignado;
    const [activo] = ok(await pasajero.rpc('mi_viaje_activo'));
    assert.equal(activo.unidad_placas, 'TAX0002');
  });

  const movimiento = esperarEvento(pasajero, 'conductor_estado', `conductor_id=eq.${c2.id}`,
    (e) => Math.abs(e.lat - 16.335) < 1e-6, 10);
  await suscrito();
  await paso('el pasajero ve al taxi moverse por Realtime', async () => {
    ok(await c2.cliente.from('conductor_estado')
      .update({ ubicacion: `SRID=4326;POINT(${ORIGEN.lng} 16.335)` }).eq('conductor_id', c2.id));
    await movimiento;
  });

  await paso('llegué → inicié → terminé', async () => {
    for (const estado of ['conductor_llego', 'en_curso', 'completado']) {
      const v = ok(await c2.cliente.rpc('avanzar_viaje', { p_viaje_id: viaje.id, p_estado: estado }));
      assert.equal(v.estado, estado);
    }
    const [ce] = ok(await c2.cliente.from('conductor_estado').select('estado').eq('conductor_id', c2.id));
    assert.equal(ce.estado, 'disponible');
  });

  await paso('el pasajero ve el viaje en su historial', async () => {
    const historial = ok(await pasajero.from('viajes').select('id, estado, tarifa_monto'));
    assert.equal(historial.length, 1);
    assert.equal(historial[0].estado, 'completado');
  });

  console.log('\nTodo bien ✔');
}

main()
  .catch((error) => {
    console.error('\n✘ Falló:', error.message ?? error);
    process.exitCode = 1;
  })
  .finally(async () => {
    for (const canal of canales) await canal.unsubscribe();
    // CONSERVAR=1 deja los datos para revisarlos en Studio.
    if (process.env.CONSERVAR) return;
    if (viajesCreados.length) await admin.from('viajes').delete().in('id', viajesCreados);
    for (const id of usuariosCreados) await admin.auth.admin.deleteUser(id);
  });
