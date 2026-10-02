import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_core/taxi_core.dart';

import '../datos.dart';

/// Lo que el pasajero pidió. Se guarda en el teléfono ANTES de enviarse,
/// con un identificador fijo: si no hay señal se reintenta, y si el servidor
/// ya la había recibido devuelve el mismo viaje (no se pide dos veces).
class Solicitud {
  Solicitud({
    required this.id,
    required this.origen,
    this.origenReferencia,
    this.destino,
    this.destinoReferencia,
  });

  factory Solicitud.fromJson(Map<String, dynamic> j) => Solicitud(
        id: j['id'] as String,
        origen: LatLng((j['origen_lat'] as num).toDouble(), (j['origen_lng'] as num).toDouble()),
        origenReferencia: j['origen_referencia'] as String?,
        destino: j['destino_lat'] == null
            ? null
            : LatLng((j['destino_lat'] as num).toDouble(), (j['destino_lng'] as num).toDouble()),
        destinoReferencia: j['destino_referencia'] as String?,
      );

  final String id;
  final LatLng origen;
  final String? origenReferencia;
  final LatLng? destino;
  final String? destinoReferencia;

  Map<String, dynamic> toJson() => {
        'id': id,
        'origen_lat': origen.latitude,
        'origen_lng': origen.longitude,
        'origen_referencia': origenReferencia,
        'destino_lat': destino?.latitude,
        'destino_lng': destino?.longitude,
        'destino_referencia': destinoReferencia,
      };
}

sealed class EstadoEnvio {
  const EstadoEnvio();
}

class SinEnvio extends EstadoEnvio {
  const SinEnvio();
}

class Enviando extends EstadoEnvio {
  const Enviando();
}

/// Sin señal: se sigue intentando solo.
class EsperandoSenal extends EstadoEnvio {
  const EsperandoSenal();
}

class EnvioRechazado extends EstadoEnvio {
  const EnvioRechazado(this.mensaje);
  final String mensaje;
}

const _kSolicitud = 'solicitud_pendiente';

final envioSolicitudProvider = NotifierProvider<EnvioSolicitud, EstadoEnvio>(EnvioSolicitud.new);

class EnvioSolicitud extends Notifier<EstadoEnvio> {
  Timer? _reintento;

  @override
  EstadoEnvio build() {
    ref.onDispose(() => _reintento?.cancel());
    ref.listen(hayRedProvider, (_, hayRed) {
      if (hayRed.value == true && state is EsperandoSenal) _reintentar();
    });
    // Si la app se cerró con una solicitud sin enviar, se retoma.
    Future.microtask(_reintentar);
    return const SinEnvio();
  }

  Future<void> pedir(Solicitud solicitud) async {
    await SharedPreferencesAsync().setString(_kSolicitud, jsonEncode(solicitud.toJson()));
    await _enviar(solicitud);
  }

  void descartarAviso() => state = const SinEnvio();

  Future<void> _reintentar() async {
    final guardada = await SharedPreferencesAsync().getString(_kSolicitud);
    if (guardada != null) await _enviar(Solicitud.fromJson(jsonDecode(guardada) as Map<String, dynamic>));
  }

  Future<void> _enviar(Solicitud s) async {
    if (state is Enviando) return;
    _reintento?.cancel();
    state = const Enviando();
    try {
      await ref.read(supabaseProvider).rpc('solicitar_viaje', params: {
        'p_client_request_id': s.id,
        'p_origen_lat': s.origen.latitude,
        'p_origen_lng': s.origen.longitude,
        'p_origen_referencia': ?s.origenReferencia,
        'p_destino_lat': ?s.destino?.latitude,
        'p_destino_lng': ?s.destino?.longitude,
        'p_destino_referencia': ?s.destinoReferencia,
      });
      await SharedPreferencesAsync().remove(_kSolicitud);
      state = const SinEnvio();
      ref.invalidate(viajeActivoProvider);
    } catch (e) {
      if (esErrorDeRed(e)) {
        state = const EsperandoSenal();
        _reintento = Timer(const Duration(seconds: 5), _reintentar);
      } else {
        // Regla de negocio (número bloqueado, ya tiene un viaje…): no se reintenta.
        await SharedPreferencesAsync().remove(_kSolicitud);
        state = EnvioRechazado(mensajeDeError(e));
        ref.invalidate(viajeActivoProvider);
      }
    }
  }
}
