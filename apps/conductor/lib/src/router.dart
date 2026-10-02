import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taxi_core/taxi_core.dart';

import 'inicio/pantalla_inicio.dart';
import 'sesion/pantalla_login.dart';

/// Rutas de la app. Sin sesión → /login; con sesión → inicio.
/// La sesión se guarda en el teléfono, así que al abrir la app (o al volver
/// la señal) el conductor sigue donde estaba sin volver a escribir su clave.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final refresco = _AlCambiarSesion(auth.onAuthStateChange);
  ref.onDispose(refresco.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresco,
    redirect: (context, state) {
      final conSesion = auth.currentSession != null;
      final enLogin = state.matchedLocation == '/login';
      if (!conSesion) return enLogin ? null : '/login';
      if (enLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const PantallaLogin()),
      GoRoute(path: '/', builder: (context, state) => const PantallaInicio()),
    ],
  );
});

/// Avisa al router cada vez que cambia la sesión (inicio, cierre, token nuevo).
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
