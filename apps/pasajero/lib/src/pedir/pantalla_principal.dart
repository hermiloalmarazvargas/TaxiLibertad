import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:taxi_core/taxi_core.dart';

import '../datos.dart';
import '../sitios.dart';
import '../viaje/pantalla_seguimiento.dart';
import 'pantalla_pedir.dart';

/// Con un viaje en curso muestra el seguimiento; si no, la pantalla para pedir.
class PantallaPrincipal extends ConsumerStatefulWidget {
  const PantallaPrincipal({super.key});

  @override
  ConsumerState<PantallaPrincipal> createState() => _PantallaPrincipalState();
}

class _PantallaPrincipalState extends ConsumerState<PantallaPrincipal> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) ref.invalidate(viajeActivoProvider);
  }

  /// Cuando el viaje desaparece de "activos", se consulta cómo terminó.
  Future<void> _avisarFin(ViajePasajero anterior) async {
    final fila = await ref
        .read(supabaseProvider)
        .from('viajes')
        .select('estado, tarifa_monto')
        .eq('id', anterior.id)
        .maybeSingle()
        .catchError((_) => null);
    if (fila == null || !mounted) return;
    final (titulo, cuerpo) = switch (fila['estado']) {
      'completado' => ('¡Llegaste!', 'Gracias por viajar con nosotros. Tarifa: ${textoTarifa((fila['tarifa_monto'] as num?)?.toDouble())}.'),
      'sin_conductor' => ('No encontramos taxi', 'Todos los taxis están ocupados. Intenta de nuevo en unos minutos.'),
      'cancelado' => ('Viaje cancelado', 'Tu viaje se canceló.'),
      _ => (null, null),
    };
    if (titulo == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(cuerpo!, style: const TextStyle(fontSize: 18)),
              // Sin taxi por la app: ofrecer llamar al sitio directamente.
              if (fila['estado'] == 'sin_conductor') ...[
                const SizedBox(height: 16),
                const Text('También puedes llamar al sitio:', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                const LlamarAlSitio(),
              ],
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(viajeActivoProvider, (antes, ahora) {
      final anterior = antes?.value;
      if (anterior != null && ahora.hasValue && ahora.value == null) _avisarFin(anterior);
    });
    final viaje = ref.watch(viajeActivoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Taxi Miahuatlán'),
        actions: [
          PopupMenuButton<String>(
            iconSize: 32,
            tooltip: 'Menú',
            onSelected: (opcion) {
              if (opcion == 'sitio') {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => const SafeArea(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Llamar al sitio', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                          SizedBox(height: 12),
                          LlamarAlSitio(),
                        ],
                      ),
                    ),
                  ),
                );
              } else {
                context.push(opcion);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: '/viajes', height: 56, child: Text('Mis viajes', style: TextStyle(fontSize: 18))),
              PopupMenuItem(value: '/perfil', height: 56, child: Text('Mis datos', style: TextStyle(fontSize: 18))),
              PopupMenuItem(value: 'sitio', height: 56, child: Text('Llamar al sitio', style: TextStyle(fontSize: 18))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const BannerConexion(),
          Expanded(
            child: viaje.when(
              data: (v) => v == null ? const PantallaPedir() : PantallaSeguimiento(viaje: v),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MensajeError(mensajeDeError(e)),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(viajeActivoProvider),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
