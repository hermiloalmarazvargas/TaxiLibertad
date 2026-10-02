import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

/// Inicia Supabase. La sesión se guarda en el teléfono: si la app se cierra
/// o se cae la señal, el usuario sigue con su sesión al volver.
Future<void> iniciarSupabase() async {
  ConfigTaxi.validar();
  await Supabase.initialize(
    url: ConfigTaxi.supabaseUrl,
    publishableKey: ConfigTaxi.supabasePublishableKey,
  );
}

/// Cliente de Supabase (se puede sustituir en pruebas).
final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Cambios de sesión: inicio, cierre y renovación del token.
final estadoSesionProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});
