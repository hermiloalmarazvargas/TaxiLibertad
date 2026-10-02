import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_core/taxi_core.dart';

import '../inicio/datos.dart';
import 'datos_viaje.dart';

/// "Llegué", "Inicié viaje" o "Terminé viaje" que todavía no llega al servidor.
class AccionPendiente {
  const AccionPendiente({required this.viajeId, required this.estado, required this.ocurridoEn});

  factory AccionPendiente.fromJson(Map<String, dynamic> json) => AccionPendiente(
        viajeId: json['viaje_id'] as String,
        estado: json['estado'] as String,
        ocurridoEn: DateTime.parse(json['ocurrido_en'] as String),
      );

  final String viajeId;

  /// 'conductor_llego' | 'en_curso' | 'completado'
  final String estado;

  /// Hora del teléfono al tocar el botón (el servidor la acota si viene rara).
  final DateTime ocurridoEn;

  Map<String, dynamic> toJson() => {
        'viaje_id': viajeId,
        'estado': estado,
        'ocurrido_en': ocurridoEn.toUtc().toIso8601String(),
      };
}

enum ResultadoEnvio {
  enviado,

  /// Sin señal: se queda en la cola y se reintenta.
  sinConexion,

  /// El servidor la rechazó por una regla (p. ej. el viaje fue cancelado):
  /// reintentar no sirve, se descarta.
  descartado,
}

/// Envía la cola en orden. Se detiene en el primer envío sin señal para no
/// mandar "Terminé" antes que "Inicié". Función pura: se prueba sin red.
Future<({List<AccionPendiente> pendientes, List<AccionPendiente> descartadas, int enviadas})> procesarCola(
  List<AccionPendiente> cola,
  Future<ResultadoEnvio> Function(AccionPendiente) enviar,
) async {
  final pendientes = [...cola];
  final descartadas = <AccionPendiente>[];
  var enviadas = 0;
  while (pendientes.isNotEmpty) {
    final resultado = await enviar(pendientes.first);
    if (resultado == ResultadoEnvio.sinConexion) break;
    final accion = pendientes.removeAt(0);
    if (resultado == ResultadoEnvio.descartado) {
      descartadas.add(accion);
    } else {
      enviadas++;
    }
  }
  return (pendientes: pendientes, descartadas: descartadas, enviadas: enviadas);
}

const _kCola = 'cola_acciones_viaje';

/// Cola guardada en el teléfono: sobrevive a que se cierre la app sin señal.
/// Se reintenta cada 10 s y en cuanto vuelve la red.
final colaAccionesProvider = NotifierProvider<ColaAcciones, List<AccionPendiente>>(ColaAcciones.new);

class ColaAcciones extends Notifier<List<AccionPendiente>> {
  bool _procesando = false;
  final _soltados = <String>{};

  /// Viajes que el propio conductor soltó (para no avisarle "te cancelaron").
  void marcarSoltado(String viajeId) => _soltados.add(viajeId);
  bool fueSoltado(String viajeId) => _soltados.contains(viajeId);

  @override
  List<AccionPendiente> build() {
    final reintento = Timer.periodic(const Duration(seconds: 10), (_) => procesar());
    ref.onDispose(reintento.cancel);
    ref.listen(hayRedProvider, (_, hayRed) {
      if (hayRed.value == true) procesar();
    });
    Future.microtask(_cargar);
    return const [];
  }

  Future<void> _cargar() async {
    final guardada = await SharedPreferencesAsync().getString(_kCola);
    if (guardada != null) {
      final lista = (jsonDecode(guardada) as List).cast<Map<String, dynamic>>();
      state = [...lista.map(AccionPendiente.fromJson), ...state];
    }
    await procesar();
  }

  Future<void> _guardar() =>
      SharedPreferencesAsync().setString(_kCola, jsonEncode(state.map((a) => a.toJson()).toList()));

  Future<void> agregar(AccionPendiente accion) async {
    state = [...state, accion];
    await _guardar();
    await procesar();
  }

  /// Último paso todavía sin enviar para un viaje (para mostrarlo ya en pantalla).
  String? estadoPendiente(String viajeId) =>
      state.where((a) => a.viajeId == viajeId).map((a) => a.estado).lastOrNull;

  Future<void> procesar() async {
    if (_procesando || state.isEmpty) return;
    _procesando = true;
    try {
      final supabase = ref.read(supabaseProvider);
      final resultado = await procesarCola(state, (accion) async {
        try {
          await supabase.rpc('avanzar_viaje', params: {
            'p_viaje_id': accion.viajeId,
            'p_estado': accion.estado,
            'p_ocurrido_en': accion.ocurridoEn.toUtc().toIso8601String(),
          });
          return ResultadoEnvio.enviado;
        } catch (e) {
          return esErrorDeRed(e) ? ResultadoEnvio.sinConexion : ResultadoEnvio.descartado;
        }
      });
      state = resultado.pendientes;
      await _guardar();
      if (resultado.enviadas > 0 || resultado.descartadas.isNotEmpty) {
        ref.invalidate(viajeActivoProvider);
        ref.invalidate(datosConductorProvider);
      }
    } finally {
      _procesando = false;
    }
  }
}
