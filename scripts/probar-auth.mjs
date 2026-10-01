// Prueba de punta a punta del flujo de autenticación contra Supabase LOCAL.
// Crea usuarios temporales, verifica el rol en el token y los borra al final.
//
// Uso: npm run probar:auth
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

const claimsDe = (session) =>
  JSON.parse(Buffer.from(session.access_token.split('.')[1], 'base64url').toString());

const creados = [];
const TEL_PRUEBA = '+529519990001';

async function paso(nombre, fn) {
  await fn();
  console.log(`  ✔ ${nombre}`);
}

async function main() {
  console.log('Personal (usuario y contraseña)');
  const usuario = `prueba.${Date.now().toString(36)}`;
  const password = 'clave1234';
  const { data: u, error } = await admin.auth.admin.createUser({
    email: correoDeUsuario(usuario), password, email_confirm: true, app_metadata: { alta: 'admin' },
  });
  if (error) throw error;
  creados.push(u.user.id);
  const { error: errPerfil } = await admin
    .from('perfiles').insert({ id: u.user.id, rol: 'despachador', nombre: 'Prueba Despacho', usuario });
  if (errPerfil) throw errPerfil;

  await paso('inicia sesión y el token trae rol=despachador', async () => {
    const { data, error } = await nuevoCliente().auth.signInWithPassword({
      email: correoDeUsuario(usuario), password,
    });
    assert.ifError(error);
    assert.equal(claimsDe(data.session).rol, 'despachador');
  });

  await paso('contraseña incorrecta es rechazada', async () => {
    const { error } = await nuevoCliente().auth.signInWithPassword({
      email: correoDeUsuario(usuario), password: 'otra1234',
    });
    assert.ok(error);
  });

  await paso('nadie puede registrarse solo con correo', async () => {
    const { error } = await nuevoCliente().auth.signUp({
      email: `intruso.${Date.now()}@ejemplo.com`, password: 'clave1234',
      options: { data: { rol: 'admin' } },
    });
    assert.ok(error, 'signUp por correo debería estar desactivado');
  });

  await paso('cuenta desactivada ya no puede iniciar sesión', async () => {
    await admin.from('perfiles').update({ activo: false }).eq('id', u.user.id);
    const { error } = await nuevoCliente().auth.signInWithPassword({
      email: correoDeUsuario(usuario), password,
    });
    assert.ok(error, 'debería rechazarse');
  });

  console.log('Pasajero (anónimo + registro)');
  const pasajero = nuevoCliente();
  const { data: anon, error: errAnon } = await pasajero.auth.signInAnonymously();
  if (errAnon) throw errAnon;
  creados.push(anon.user.id);

  await paso('sesión anónima sin rol', async () => {
    assert.equal(claimsDe(anon.session).rol, undefined);
    assert.equal(claimsDe(anon.session).is_anonymous, true);
  });

  await paso('registrar_pasajero + refreshSession → rol=pasajero', async () => {
    const { error } = await pasajero.rpc('registrar_pasajero', {
      p_nombre: 'Pasajero Prueba', p_telefono: '951 999 0001',
    });
    assert.ifError(error);
    const { data, error: errRefresh } = await pasajero.auth.refreshSession();
    assert.ifError(errRefresh);
    assert.equal(claimsDe(data.session).rol, 'pasajero');
  });

  await paso('al bloquear su número ya no puede renovar el token', async () => {
    await admin.from('telefonos_bloqueados').insert({ telefono: TEL_PRUEBA, motivo: 'prueba' });
    const { error } = await pasajero.auth.refreshSession();
    assert.ok(error, 'debería rechazarse');
  });

  console.log('\nTodo bien ✔');
}

main()
  .catch((error) => {
    console.error('\n✘ Falló:', error.message ?? error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await admin.from('telefonos_bloqueados').delete().eq('telefono', TEL_PRUEBA);
    for (const id of creados) await admin.auth.admin.deleteUser(id);
  });
