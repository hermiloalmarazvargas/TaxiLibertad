import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:taxi_core/taxi_core.dart';

double? _num(Object? v) => (v as num?)?.toDouble();

/// Viaje en curso del pasajero, con los datos del taxi para reconocerlo.
class ViajePasajero {
  ViajePasajero.desdeFila(Map<String, dynamic> f)
      : id = f['viaje_id'] as String,
        estado = f['estado'] as String,
        origen = LatLng(_num(f['origen_lat'])!, _num(f['origen_lng'])!),
        origenReferencia = f['origen_referencia'] as String?,
        destino = f['destino_lat'] == null ? null : LatLng(_num(f['destino_lat'])!, _num(f['destino_lng'])!),
        destinoReferencia = f['destino_referencia'] as String?,
        tarifa = _num(f['tarifa_monto']),
        conductor = f['conductor_nombre'] as String?,
        unidadNumero = f['unidad_numero'] as String?,
        unidadPlacas = f['unidad_placas'] as String?,
        unidadDescripcion = f['unidad_descripcion'] as String?,
        posicionTaxi = f['conductor_lat'] == null ? null : LatLng(_num(f['conductor_lat'])!, _num(f['conductor_lng'])!);

  final String id;

  /// 'buscando' | 'asignado' | 'conductor_llego' | 'en_curso'
  final String estado;
  final LatLng origen;
  final String? origenReferencia;
  final LatLng? destino;
  final String? destinoReferencia;
  final double? tarifa;
  final String? conductor;
  final String? unidadNumero;
  final String? unidadPlacas;
  final String? unidadDescripcion;
  final LatLng? posicionTaxi;
}

final viajeActivoProvider = FutureProvider<ViajePasajero?>((ref) async {
  final filas = await ref.watch(supabaseProvider).rpc('mi_viaje_activo') as List;
  return filas.isEmpty ? null : ViajePasajero.desdeFila(filas.first as Map<String, dynamic>);
});

/// Tarifa estimada (con recargo nocturno si aplica). monto null = a convenir.
typedef Tarifa = ({double? monto, double? recargo, bool nocturno, String? zonaOrigen, String? zonaDestino});

Future<Tarifa> tarifaEstimada(WidgetRef ref, LatLng origen, LatLng? destino) async {
  final filas = await ref.read(supabaseProvider).rpc('tarifa_estimada', params: {
    'origen_lat': origen.latitude,
    'origen_lng': origen.longitude,
    'destino_lat': ?destino?.latitude,
    'destino_lng': ?destino?.longitude,
  }) as List;
  final f = filas.first as Map<String, dynamic>;
  return (
    monto: _num(f['monto']),
    recargo: _num(f['recargo']),
    nocturno: f['nocturno'] == true,
    zonaOrigen: f['zona_origen'] as String?,
    zonaDestino: f['zona_destino'] as String?,
  );
}

String textoTarifa(double? monto) =>
    monto == null ? 'A convenir' : '\$${monto % 1 == 0 ? monto.toStringAsFixed(0) : monto.toStringAsFixed(2)}';
