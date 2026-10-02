/// El personal inicia sesión con "usuario"; Auth necesita un correo, así que
/// se usa uno interno que nadie ve. Debe coincidir con el panel y con las
/// Edge Functions (`usuarios.taxi.internal`).
const dominioUsuarios = 'usuarios.taxi.internal';

String correoDeUsuario(String usuario) => '${usuario.trim().toLowerCase()}@$dominioUsuarios';
