import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taxi_core/taxi_core.dart';

import 'historial/pantalla_historial.dart';
import 'pedir/pantalla_principal.dart';
import 'perfil/pantalla_perfil.dart';
import 'registro/pantalla_registro.dart';

/// Sin registro completo (sesión con rol "pasajero") → /registro.
/// La sesión se guarda en el teléfono: el pasajero se registra una sola vez.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresco = _AlCambiarSesion(auth.onAuthStateChange);
  ref.onDispose(refresco.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresco,
    redirect: (context, state) {
      final token = auth.currentSession?.accessToken;
      final registrado = token != null && leerClaims(token).rol == 'pasajero';
      final enRegistro = state.matchedLocation == '/registro';
      if (!registrado) return enRegistro ? null : '/registro';
      if (enRegistro) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/registro', builder: (context, state) => const PantallaRegistro()),
      GoRoute(path: '/', builder: (context, state) => const PantallaPrincipal()),
      GoRoute(path: '/viajes', builder: (context, state) => const PantallaHistorial()),
      GoRoute(path: '/perfil', builder: (context, state) => const PantallaPerfil()),
    ],
  );
});

class _AlCambiarSesion extends ChangeNotifier {
  _AlCambiarSesion(Stream<AuthState> cambios) {
    _suscripcion = cambios.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _suscripcion;

  @override
  void dispose() {
    _suscripcion.cancel();
    super.dispose();
  }
}
