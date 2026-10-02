import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taxi_core/taxi_core.dart';

import '../datos.dart';

/// Seguimiento del viaje: estado en vivo, el taxi acercándose en el mapa y
/// sus datos para reconocerlo (número, placas, color).
class PantallaSeguimiento extends ConsumerStatefulWidget {
  const PantallaSeguimiento({super.key, required this.viaje});

  final ViajePasajero viaje;

  @override
  ConsumerState<PantallaSeguimiento> createState() => _PantallaSeguimientoState();
}

class _PantallaSeguimientoState extends ConsumerState<PantallaSeguimiento> {
  final _mapa = MapController();
  RealtimeChannel? _canal;
  LatLng? _taxi;
  bool _cancelando = false;
  String? _error;

  SupabaseClient get _supabase => ref.read(supabaseProvider);

  @override
  void initState() {
    super.initState();
    _taxi = widget.viaje.posicionTaxi;
    // La ubicación del taxi llega por Realtime (RLS solo deja ver la del taxi
    // de su propio viaje activo); el estado del viaje también.
    _canal = _supabase
        .channel('viaje-${widget.viaje.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conductor_estado',
          callback: (cambio) {
            final lat = cambio.newRecord['lat'] as num?;
            final lng = cambio.newRecord['lng'] as num?;
            if (lat != null && lng != null && mounted) {
              setState(() => _taxi = LatLng(lat.toDouble(), lng.toDouble()));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'viajes',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.viaje.id),
          callback: (_) => ref.invalidate(viajeActivoProvider),
        )
        .subscribe((estado, _) {
      // Al (re)conectar, ponerse al día por si algo pasó sin señal.
      if (estado == RealtimeSubscribeStatus.subscribed) ref.invalidate(viajeActivoProvider);
    });
  }

  @override
  void didUpdateWidget(PantallaSeguimiento anterior) {
    super.didUpdateWidget(anterior);
    final v = widget.viaje;
    if (v.posicionTaxi != null) _taxi = v.posicionTaxi;
    // "¡Tu taxi llegó!": vibra para que el pasajero se entere.
    if (anterior.viaje.estado != 'conductor_llego' && v.estado == 'conductor_llego') {
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    final canal = _canal;
    if (canal != null) _supabase.removeChannel(canal);
    super.dispose();
  }

  Future<void> _cancelar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar el taxi?'),
        content: Text(
          widget.viaje.estado == 'buscando'
              ? 'Dejaremos de buscarte un taxi.'
              : 'El taxi ya va en camino. Cancela solo si de verdad ya no lo necesitas.',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _cancelando = true;
      _error = null;
    });
    try {
      await _supabase.rpc('cancelar_viaje', params: {
        'p_viaje_id': widget.viaje.id,
        'p_motivo': 'Cancelado por el pasajero',
      });
      ref.invalidate(viajeActivoProvider);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.viaje;
    final texto = Theme.of(context).textTheme;
    final (titulo, detalle, color) = switch (v.estado) {
      'buscando' => ('Buscando un taxi…', 'Le estamos avisando al taxi más cercano.', ColoresTaxi.ambar),
      'asignado' => ('Tu taxi viene en camino', 'Espera en el lugar que marcaste.', ColoresTaxi.verde),
      'conductor_llego' => ('¡Tu taxi llegó!', 'Sal a encontrarlo.', ColoresTaxi.verde),
      _ => ('En viaje', 'Buen viaje.', ColoresTaxi.verde),
    };
    final puntos = [v.origen, ?_taxi];

    return Column(
      children: [
        Expanded(
          child: !hayKeyDeMapa
              ? const AvisoSinMapa()
              : FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCameraFit: puntos.length > 1
                        ? CameraFit.coordinates(coordinates: puntos, padding: const EdgeInsets.all(72), maxZoom: 17)
                        : null,
                    initialCenter: v.origen,
                    initialZoom: 16,
                  ),
                  children: [
                    ...capasBaseMapa(paquete: 'mx.taximiahuatlan.pasajero'),
                    MarkerLayer(markers: [
                      Marker(
                        point: v.origen,
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.person_pin_circle, size: 48, color: ColoresTaxi.tinta),
                      ),
                      if (_taxi != null && v.estado != 'buscando')
                        Marker(
                          point: _taxi!,
                          width: 52,
                          height: 52,
                          child: Container(
                            decoration: BoxDecoration(
                              color: ColoresTaxi.ambar,
                              shape: BoxShape.circle,
                              border: Border.all(color: ColoresTaxi.tinta, width: 3),
                            ),
                            child: const Icon(Icons.local_taxi, color: ColoresTaxi.tinta, size: 30),
                          ),
                        ),
                    ]),
                  ],
                ),
        ),
        Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(titulo, style: texto.headlineMedium?.copyWith(color: color)),
                ),
                Text(detalle, style: texto.bodyLarge),
                if (v.unidadNumero != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Taxi ${v.unidadNumero} · ${v.unidadPlacas}', style: texto.titleLarge),
                        if (v.unidadDescripcion != null) Text(v.unidadDescripcion!, style: texto.bodyLarge),
                        if (v.conductor != null) Text('Conductor: ${v.conductor}', style: texto.bodyLarge),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text('Tarifa: ${textoTarifa(v.tarifa)} · en efectivo', style: texto.bodyLarge),
                if (v.estado == 'buscando') ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 6, color: ColoresTaxi.ambar),
                ],
                const SizedBox(height: 12),
                MensajeError(_error),
                if (v.estado != 'en_curso')
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ColoresTaxi.rojo,
                      side: const BorderSide(color: ColoresTaxi.rojo, width: 2),
                    ),
                    onPressed: _cancelando ? null : _cancelar,
                    child: const Text('Cancelar taxi'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
