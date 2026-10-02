import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conexion.dart';
import '../tema.dart';

/// Franja roja visible cuando el teléfono no tiene red. No bloquea la
/// pantalla: lo que el usuario haga se guarda y se reintenta.
class BannerConexion extends ConsumerWidget {
  const BannerConexion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hayRed = ref.watch(hayRedProvider).value ?? true;
    if (hayRed) return const SizedBox.shrink();

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: ColoresTaxi.rojo,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Text(
          'Sin señal. Seguimos intentando…',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
