import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';

double? _num(Object? v) => (v as num?)?.toDouble();

/// Oferta que el conductor debe aceptar o rechazar (sin datos personales del pasajero).
class Oferta {
  Oferta.desdeFila(Map<String, dynamic> f)
      : id = f['oferta_id'] as int,
        viajeId = f['viaje_id'] as String,
        segundosRestantes = f['segundos_restantes'] as int,
        distanciaM = f['distancia_m'] as int?,
        origenLat = _num(f['origen_lat'])!,
        origenLng = _num(f['origen_lng'])!,
        origenReferencia = f['origen_referencia'] as String?,
        destinoReferencia = f['destino_referencia'] as String?,
        zonaOrigen = f['zona_origen'] as String?,
        zonaDestino = f['zona_destino'] as String?,
        tarifa = _num(f['tarifa_monto']);

  final int id;
  final String viajeId;

  /// Calculado en el servidor: el reloj del teléfono puede estar mal.
  final int segundosRestantes;
  final int? distanciaM;
  final double origenLat;
  final double origenLng;
  final String? origenReferencia;
  final String? destinoReferencia;
  final String? zonaOrigen;
  final String? zonaDestino;

  /// null = a convenir.
  final double? tarifa;
}

final ofertaPendienteProvider = FutureProvider<Oferta?>((ref) async {
  final filas = await ref.watch(supabaseProvider).rpc('mi_oferta_pendiente') as List;
  return filas.isEmpty ? null : Oferta.desdeFila(filas.first as Map<String, dynamic>);
});

/// Viaje que el conductor está atendiendo.
class ViajeActivo {
  ViajeActivo.desdeFila(Map<String, dynamic> f)
      : id = f['viaje_id'] as String,
        estado = f['estado'] as String,
        porTelefono = f['canal'] == 'telefono',
        origenLat = _num(f['origen_lat'])!,
        origenLng = _num(f['origen_lng'])!,
        origenReferencia = f['origen_referencia'] as String?,
        destinoLat = _num(f['destino_lat']),
        destinoLng = _num(f['destino_lng']),
        destinoReferencia = f['destino_referencia'] as String?,
        zonaOrigen = f['zona_origen'] as String?,
        zonaDestino = f['zona_destino'] as String?,
        tarifa = _num(f['tarifa_monto']),
        pasajeroNombre = f['pasajero_nombre'] as String?,
        pasajeroTelefono = f['pasajero_telefono'] as String?;

  final String id;

  /// 'asignado' | 'conductor_llego' | 'en_curso'
  final String estado;
  final bool porTelefono;
  final double origenLat;
  final double origenLng;
  final String? origenReferencia;
  final double? destinoLat;
  final double? destinoLng;
  final String? destinoReferencia;
  final String? zonaOrigen;
  final String? zonaDestino;
  final double? tarifa;
  final String? pasajeroNombre;
  final String? pasajeroTelefono;
}

final viajeActivoProvider = FutureProvider<ViajeActivo?>((ref) async {
  final filas = await ref.watch(supabaseProvider).rpc('mi_viaje_activo_conductor') as List;
  return filas.isEmpty ? null : ViajeActivo.desdeFila(filas.first as Map<String, dynamic>);
});

String textoTarifa(double? tarifa) =>
    tarifa == null ? 'A convenir' : '\$${tarifa % 1 == 0 ? tarifa.toStringAsFixed(0) : tarifa.toStringAsFixed(2)}';

String textoDistancia(int metros) =>
    metros < 1000 ? '${(metros / 10).round() * 10} m' : '${(metros / 1000).toStringAsFixed(1)} km';
