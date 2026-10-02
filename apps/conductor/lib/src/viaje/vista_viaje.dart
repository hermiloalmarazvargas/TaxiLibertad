import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';

import '../inicio/datos.dart';
import 'cola_acciones.dart';
import 'datos_viaje.dart';
import 'navegacion.dart';

/// El viaje que el conductor está atendiendo: datos del pasajero, ruta y el
/// botón del siguiente paso (Llegué → Inicié → Terminé).
///
/// Los pasos se guardan en una cola en el teléfono: si no hay señal, la
/// pantalla avanza igual y el paso se envía solo cuando vuelva la red.
class VistaViaje extends ConsumerStatefulWidget {
  const VistaViaje({super.key, required this.viaje});

  final ViajeActivo viaje;

  @override
  ConsumerState<VistaViaje> createState() => _VistaViajeState();
}

class _VistaViajeState extends ConsumerState<VistaViaje> {
  bool _soltando = false;
  String? _error;

  Future<void> _avanzar(String estado) async {
    await ref.read(colaAccionesProvider.notifier).agregar(
          AccionPendiente(viajeId: widget.viaje.id, estado: estado, ocurridoEn: DateTime.now()),
        );
  }

  Future<void> _terminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Terminaste el viaje?'),
        content: Text(
          widget.viaje.tarifa == null
              ? 'Cobra lo que acordaste con el pasajero.'
              : 'Cobra ${textoTarifa(widget.viaje.tarifa)} en efectivo.',
          style: const TextStyle(fontSize: 22),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Todavía no')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, terminé')),
        ],
      ),
    );
    if (ok == true) await _avanzar('completado');
  }

  Future<void> _soltar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Soltar el viaje?'),
        content: const Text('Se le ofrecerá a otro taxi. Hazlo solo si de verdad no puedes ir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, soltar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _soltando = true;
      _error = null;
    });
    ref.read(colaAccionesProvider.notifier).marcarSoltado(widget.viaje.id);
    try {
      await ref.read(supabaseProvider).rpc('cancelar_viaje', params: {
        'p_viaje_id': widget.viaje.id,
        'p_motivo': 'El conductor soltó el viaje',
      });
      ref.invalidate(viajeActivoProvider);
      ref.invalidate(datosConductorProvider);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _soltando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.viaje;
    final cola = ref.watch(colaAccionesProvider);
    final pendiente = ref.read(colaAccionesProvider.notifier).estadoPendiente(v.id);
    // Lo que el conductor ya tocó manda, aunque todavía no llegue al servidor.
    final estado = pendiente ?? v.estado;
    final sinEnviar = cola.any((a) => a.viajeId == v.id);
    final texto = Theme.of(context).textTheme;

    final (titulo, hacia) = switch (estado) {
      'asignado' => ('Ve por el pasajero', (v.origenLat, v.origenLng)),
      'conductor_llego' => ('Espera al pasajero', (v.origenLat, v.origenLng)),
      'en_curso' => (
          'En viaje',
          v.destinoLat != null ? (v.destinoLat!, v.destinoLng!) : null,
        ),
      _ => ('Viaje terminado', null),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: texto.headlineMedium),
        if (sinEnviar)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
            child: const Text(
              '⏳ Pendiente de enviar: se mandará solo cuando haya señal.',
              style: TextStyle(fontSize: 17),
            ),
          ),
        const SizedBox(height: 16),
        _Tarjeta(
          children: [
            Text(v.pasajeroNombre ?? 'Pasajero', style: texto.titleLarge),
            Text(v.porTelefono ? 'Pidió por teléfono' : 'Pidió por la app', style: texto.bodyMedium),
            const SizedBox(height: 12),
            Text('Recoger en', style: texto.bodyMedium?.copyWith(color: ColoresTaxi.gris)),
            Text(v.origenReferencia ?? 'Sin referencia', style: texto.titleLarge),
            if (v.zonaOrigen != null) Text(v.zonaOrigen!, style: texto.bodyLarge),
            const SizedBox(height: 12),
            Text('Destino', style: texto.bodyMedium?.copyWith(color: ColoresTaxi.gris)),
            Text(v.destinoReferencia ?? v.zonaDestino ?? 'No indicado', style: texto.titleLarge),
            const SizedBox(height: 12),
            Text('Tarifa: ${textoTarifa(v.tarifa)}', style: texto.titleLarge),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (v.pasajeroTelefono != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => llamar(v.pasajeroTelefono!),
                  icon: const Icon(Icons.phone, size: 28),
                  label: const Text('Llamar'),
                ),
              ),
          ],
        ),
        if (hacia != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => abrirGoogleMaps(hacia.$1, hacia.$2),
                  icon: const Icon(Icons.map, size: 28),
                  label: const Text('Maps'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => abrirWaze(hacia.$1, hacia.$2),
                  icon: const Icon(Icons.navigation, size: 28),
                  label: const Text('Waze'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        ...switch (estado) {
          'asignado' => [_BotonPaso(texto: 'LLEGUÉ', onPressed: () => _avanzar('conductor_llego'))],
          'conductor_llego' => [_BotonPaso(texto: 'INICIÉ VIAJE', onPressed: () => _avanzar('en_curso'))],
          'en_curso' => [_BotonPaso(texto: 'TERMINÉ VIAJE', onPressed: _terminar)],
          _ => [Text('Listo. En cuanto se envíe, volverás a estar disponible.', style: texto.titleLarge)],
        },
        if (estado == 'asignado' || estado == 'conductor_llego') ...[
          const SizedBox(height: 24),
          MensajeError(_error),
          TextButton(
            onPressed: _soltando ? null : _soltar,
            child: const Text('No puedo ir: soltar el viaje', style: TextStyle(fontSize: 18, color: ColoresTaxi.rojo)),
          ),
        ],
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _BotonPaso extends StatelessWidget {
  const _BotonPaso({required this.texto, required this.onPressed});

  final String texto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 88,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ColoresTaxi.verde,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          onPressed: onPressed,
          child: Text(texto),
        ),
      );
}
