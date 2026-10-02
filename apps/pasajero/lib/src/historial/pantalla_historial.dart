import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';

import '../datos.dart';
import '../formato.dart';

typedef ViajeHistorial = ({
  String estado,
  DateTime fecha,
  String? origen,
  String? destino,
  double? tarifa,
});

/// Los últimos viajes del pasajero (RLS solo le deja ver los suyos).
final historialProvider = FutureProvider<List<ViajeHistorial>>((ref) async {
  final filas = await ref
      .watch(supabaseProvider)
      .from('viajes')
      .select('estado, solicitado_en, origen_referencia, destino_referencia, tarifa_monto, '
          'zona_origen:zonas!viajes_zona_origen_id_fkey(nombre), '
          'zona_destino:zonas!viajes_zona_destino_id_fkey(nombre)')
      .order('solicitado_en', ascending: false)
      .limit(50);

  String? lugar(Map<String, dynamic> f, String referencia, String zona) =>
      f[referencia] as String? ?? (f[zona] as Map<String, dynamic>?)?['nombre'] as String?;

  return [
    for (final f in filas)
      (
        estado: f['estado'] as String,
        fecha: DateTime.parse(f['solicitado_en'] as String),
        origen: lugar(f, 'origen_referencia', 'zona_origen'),
        destino: lugar(f, 'destino_referencia', 'zona_destino'),
        tarifa: (f['tarifa_monto'] as num?)?.toDouble(),
      ),
  ];
});

class PantallaHistorial extends ConsumerWidget {
  const PantallaHistorial({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historial = ref.watch(historialProvider);
    final texto = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mis viajes')),
      body: Column(
        children: [
          const BannerConexion(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(historialProvider);
                await ref.read(historialProvider.future);
              },
              child: historial.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(
                  padding: const EdgeInsets.all(20),
                  children: [MensajeError(mensajeDeError(e))],
                ),
                data: (viajes) => viajes.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(20),
                        children: [Text('Todavía no has pedido taxis.', style: texto.bodyLarge)],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: viajes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final v = viajes[i];
                          final color = switch (v.estado) {
                            'completado' => ColoresTaxi.verde,
                            'cancelado' || 'sin_conductor' => ColoresTaxi.gris,
                            _ => ColoresTaxi.ambar,
                          };
                          return Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(fechaCorta(v.fecha), style: texto.bodyMedium)),
                                      Text(textoEstado(v.estado),
                                          style: texto.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(v.origen ?? 'Punto en el mapa', style: texto.titleLarge),
                                  if (v.destino != null) Text('→ ${v.destino}', style: texto.bodyLarge),
                                  Text(textoTarifa(v.tarifa), style: texto.bodyLarge),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
