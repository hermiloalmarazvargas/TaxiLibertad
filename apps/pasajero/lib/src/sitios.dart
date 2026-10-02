import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'formato.dart';

typedef Sitio = ({String nombre, String telefono});

/// Sitios activos con teléfono (para llamar si no hay taxi por la app).
final sitiosProvider = FutureProvider<List<Sitio>>((ref) async {
  final filas = await ref
      .watch(supabaseProvider)
      .from('sitios')
      .select('nombre, telefono')
      .eq('activo', true)
      .not('telefono', 'is', null)
      .order('nombre');
  return [for (final f in filas) (nombre: f['nombre'] as String, telefono: f['telefono'] as String)];
});

/// Botones grandes para llamar a cada sitio.
class LlamarAlSitio extends ConsumerWidget {
  const LlamarAlSitio({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(sitiosProvider).when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          error: (e, _) => MensajeError(mensajeDeError(e)),
          data: (sitios) => sitios.isEmpty
              ? const Text('No hay teléfonos de sitios registrados.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in sitios)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: s.telefono)),
                          icon: const Icon(Icons.phone, size: 28),
                          label: Text('${s.nombre} · ${telefonoLegible(s.telefono)}'),
                        ),
                      ),
                  ],
                ),
        );
  }
}
