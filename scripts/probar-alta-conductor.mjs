// Prueba de punta a punta de la Edge Function "alta-conductor" (Supabase LOCAL).
//
// Uso: npm run probar:alta
import assert from 'node:assert/strict';
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

const sufijo = Date.now().toString(36);
const creados = [];

async function paso(nombre, fn) {
  await fn();
  console.log(`  ✔ ${nombre}`);
}

// Llama a la función y devuelve { status, body } (sin lanzar en 4xx).
async function alta(cliente, body) {
  const { data: { session } } = await cliente.auth.getSession();
  const res = await fetch(`${url}/functions/v1/alta-conductor`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: process.env.SUPABASE_PUBLISHABLE_KEY,
      ...(session ? { Authorization: `Bearer ${session.access_token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

async function crearPersonal(rol) {
  const usuario = `prueba.${rol}.${sufijo}`;
  const { data, error } = await admin.auth.admin.createUser({
    email: correoDeUsuario(usuario), password: 'clave1234', email_confirm: true,
    app_metadata: { alta: 'admin' },
  });
  if (error) throw error;
  creados.push(data.user.id);
  const { error: e2 } = await admin.from('perfiles').insert({ id: data.user.id, rol, nombre: `Prueba ${rol}`, usuario });
  if (e2) throw e2;
  const cliente = nuevoCliente();
  const { error: e3 } = await cliente.auth.signInWithPassword({ email: correoDeUsuario(usuario), password: 'clave1234' });
  if (e3) throw e3;
  return { id: data.user.id, cliente };
}

async function main() {
  const { data: sitio } = await admin.from('sitios').select('id').eq('nombre', 'Sitio Centro').single();
  const jefe = await crearPersonal('admin');
  const despacho = await crearPersonal('despachador');
  const usuario = `prueba.chofer.${sufijo}`;
  const datos = { nombre: 'Chofer de Prueba', usuario, sitio_id: sitio.id, telefono: '951 444 5566' };

  console.log('Permisos');
  await paso('sin sesión → 401', async () => {
    assert.equal((await alta(nuevoCliente(), datos)).status, 401);
  });
  await paso('un despachador no puede dar de alta → 403', async () => {
    assert.equal((await alta(despacho.cliente, datos)).status, 403);
  });

  console.log('Validación');
  await paso('datos inválidos → 400 con mensaje', async () => {
    const r = await alta(jefe.cliente, { ...datos, usuario: 'Con Espacios' });
    assert.equal(r.status, 400);
    assert.equal(r.body.codigo, 'entrada_invalida');
  });
  await paso('sitio inexistente → 400 y no deja cuenta a medias', async () => {
    const r = await alta(jefe.cliente, { ...datos, sitio_id: 999999 });
    assert.equal(r.status, 400);
    assert.equal(r.body.codigo, 'sitio_invalido');
    const { error } = await nuevoCliente().auth.signInWithPassword({
      email: correoDeUsuario(usuario), password: 'x',
    });
    assert.match(error.message, /invalid/i, 'la cuenta de Auth debió borrarse');
  });

  console.log('Alta');
  let password;
  await paso('el admin da de alta → 201 con contraseña generada', async () => {
    const r = await alta(jefe.cliente, datos);
    assert.equal(r.status, 201, JSON.stringify(r.body));
    creados.push(r.body.id);
    password = r.body.password;
    assert.match(password, /^(?=.*[a-z])(?=.*\d)[a-z\d]{10}$/);
  });
  await paso('usuario repetido → 409', async () => {
    const r = await alta(jefe.cliente, datos);
    assert.equal(r.status, 409);
    assert.equal(r.body.codigo, 'usuario_existe');
  });
  await paso('el conductor inicia sesión con rol y sitio en el token', async () => {
    const chofer = nuevoCliente();
    const { data, error } = await chofer.auth.signInWithPassword({ email: correoDeUsuario(usuario), password });
    assert.ifError(error);
    const claims = JSON.parse(Buffer.from(data.session.access_token.split('.')[1], 'base64url').toString());
    assert.equal(claims.rol, 'conductor');
    assert.equal(claims.sitio_id, sitio.id);
    const { data: estado } = await chofer.from('conductor_estado').select('estado').single();
    assert.equal(estado.estado, 'fuera_de_servicio');
    const { data: perfil } = await chofer.from('perfiles').select('telefono').single();
    assert.equal(perfil.telefono, '+529514445566');
  });

  console.log('\nTodo bien ✔');
}

main()
  .catch((error) => {
    console.error('\n✘ Falló:', error.message ?? error);
    process.exitCode = 1;
  })
  .finally(async () => {
    for (const id of creados) await admin.auth.admin.deleteUser(id);
  });
