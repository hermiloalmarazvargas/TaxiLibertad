/// Configuración que entra al compilar con `--dart-define-from-file`.
///
/// Las llaves NO se escriben en el código: van en `config/local.json` de cada
/// app (ignorado por git). La llave publicable es pública por diseño (todo
/// pasa por RLS); la llave secreta jamás debe estar en una app.
abstract final class ConfigTaxi {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const maptilerKey = String.fromEnvironment('MAPTILER_KEY');

  /// Lanza un error claro si se olvidó pasar la configuración al compilar.
  static void validar() {
    final faltan = [
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabasePublishableKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
    ];
    if (faltan.isNotEmpty) {
      throw StateError(
        'Falta ${faltan.join(', ')}. Ejecuta con '
        '--dart-define-from-file=config/local.json (ver config/local.example.json).',
      );
    }
  }
}
