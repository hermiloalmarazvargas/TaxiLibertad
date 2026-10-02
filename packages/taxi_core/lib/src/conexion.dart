import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Si el teléfono tiene alguna red (datos o WiFi).
///
/// Ojo: tener red no garantiza llegar al servidor (señal débil, sin saldo).
/// Por eso las acciones importantes, además, se reintentan si fallan.
final hayRedProvider = StreamProvider<bool>((ref) async* {
  final conectividad = Connectivity();
  bool hayRed(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

  yield hayRed(await conectividad.checkConnectivity());
  yield* conectividad.onConnectivityChanged.map(hayRed);
});
