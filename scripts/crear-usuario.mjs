// Crea una cuenta de personal (conductor, despachador o admin).
//
// Uso:
//   npm run usuario:crear -- --rol conductor --usuario juan.perez --nombre "Juan Pérez" --sitio "Sitio Centro"
//   npm run usuario:crear -- --rol admin --usuario admin --nombre "Administrador"
//
// Si no se indica --password, se genera una y se muestra UNA sola vez.
import { randomInt } from 'node:crypto';
import { parseArgs } from 'node:util';
import { correoDeUsuario, crearClienteAdmin } from './lib/supabase-admin.mjs';

const ROLES = ['conductor', 'despachador', 'admin'];
// Sin caracteres que se confunden al dictarlos (0/O, 1/l/I).
const LETRAS = 'abcdefghjkmnpqrstuvwxyz';
const DIGITOS = '23456789';

function generarPassword(largo = 10) {
  const todos = LETRAS + DIGITOS;
  const chars = [LETRAS[randomInt(LETRAS.length)], DIGITOS[randomInt(DIGITOS.length)]];
  while (chars.length < largo) chars.push(todos[randomInt(todos.length)]);
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

function leerArgumentos() {
  const { values } = parseArgs({
    options: {
      rol: { type: 'string' },
      usuario: { type: 'string' },
      nombre: { type: 'string' },
      sitio: { type: 'string' },
      telefono: { type: 'string' },
      password: { type: 'string' },
    },
  });

  const errores = [];
  if (!ROLES.includes(values.rol)) errores.push(`--rol debe ser: ${ROLES.join(', ')}`);
  if (!/^[a-z0-9][a-z0-9._]{2,29}$/.test(values.usuario ?? '')) {
    errores.push('--usuario: 3 a 30 caracteres, minúsculas, números, punto o guion bajo');
  }
  if (!values.nombre?.trim()) errores.push('--nombre es obligatorio');
  if (values.rol === 'conductor' && !values.sitio) errores.push('--sitio es obligatorio para conductores');
  if (errores.length) {
    console.error(errores.join('\n'));
    process.exit(1);
  }
  return values;
}

async function main() {
  const args = leerArgumentos();
  const supabase = crearClienteAdmin();

  let sitioId = null;
  if (args.sitio) {
    const { data, error } = await supabase
      .from('sitios').select('id').eq('nombre', args.sitio).maybeSingle();
    if (error) throw error;
    if (!data) throw new Error(`No existe el sitio "${args.sitio}"`);
    sitioId = data.id;
  }

  let telefono = null;
  if (args.telefono) {
    const { data, error } = await supabase.rpc('normalizar_telefono', { p_telefono: args.telefono });
    if (error) throw error;
    telefono = data;
  }

  const password = args.password ?? generarPassword();
  const { data: creado, error: errorAuth } = await supabase.auth.admin.createUser({
    email: correoDeUsuario(args.usuario),
    password,
    email_confirm: true,
    app_metadata: { alta: 'admin' },
  });
  if (errorAuth?.code === 'email_exists') throw new Error(`El usuario "${args.usuario}" ya existe`);
  if (errorAuth) throw errorAuth;
  const userId = creado.user.id;

  try {
    const { error: errorPerfil } = await supabase.from('perfiles').insert({
      id: userId,
      rol: args.rol,
      nombre: args.nombre.trim(),
      usuario: args.usuario,
      telefono,
      // En perfiles, sitio_id solo aplica a despachadores de un sitio.
      sitio_id: args.rol === 'despachador' ? sitioId : null,
    });
    if (errorPerfil) throw errorPerfil;

    if (args.rol === 'conductor') {
      const { error: errorConductor } = await supabase
        .from('conductores').insert({ perfil_id: userId, sitio_id: sitioId });
      if (errorConductor) throw errorConductor;

      const { error: errorEstado } = await supabase
        .from('conductor_estado').insert({ conductor_id: userId });
      if (errorEstado) throw errorEstado;
    }
  } catch (error) {
    // Sin perfil la cuenta no sirve: se borra (en cascada borra lo demás).
    await supabase.auth.admin.deleteUser(userId);
    throw error;
  }

  console.log(`Cuenta creada (${args.rol})`);
  console.log(`  Usuario:    ${args.usuario}`);
  console.log(`  Contraseña: ${password}${args.password ? '' : '   ← anótala, no se vuelve a mostrar'}`);
}

main().catch((error) => {
  console.error('Error:', error.message ?? error);
  process.exitCode = 1;
});
