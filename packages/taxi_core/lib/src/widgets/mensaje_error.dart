import 'package:flutter/material.dart';

import '../tema.dart';

/// Recuadro de error grande y legible. No muestra nada si [mensaje] es null.
class MensajeError extends StatelessWidget {
  const MensajeError(this.mensaje, {super.key});

  final String? mensaje;

  @override
  Widget build(BuildContext context) {
    final texto = mensaje;
    if (texto == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ColoresTaxi.rojo),
        ),
        child: Text(texto, style: const TextStyle(fontSize: 18, color: Color(0xFF7F1D1D))),
      ),
    );
  }
}
