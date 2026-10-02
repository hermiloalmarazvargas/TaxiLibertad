import 'package:conductor/src/viaje/cola_acciones.dart';
import 'package:flutter_test/flutter_test.dart';

AccionPendiente accion(String estado) =>
    AccionPendiente(viajeId: 'v1', estado: estado, ocurridoEn: DateTime(2026, 10, 1, 12));

void main() {
  final llegue = accion('conductor_llego');
  final inicie = accion('en_curso');
  final termine = accion('completado');

  test('con señal se envía todo, en orden', () async {
    final enviadas = <String>[];
    final r = await procesarCola([llegue, inicie, termine], (a) async {
      enviadas.add(a.estado);
      return ResultadoEnvio.enviado;
    });
    expect(enviadas, ['conductor_llego', 'en_curso', 'completado']);
    expect(r.pendientes, isEmpty);
    expect(r.enviadas, 3);
  });

  test('sin señal se detiene y conserva el orden para reintentar', () async {
    final r = await procesarCola([llegue, inicie, termine], (a) async =>
        a.estado == 'conductor_llego' ? ResultadoEnvio.enviado : ResultadoEnvio.sinConexion);
    expect(r.pendientes.map((a) => a.estado), ['en_curso', 'completado']);
    expect(r.enviadas, 1);
  });

  test('nunca manda "Terminé" si "Inicié" no ha llegado', () async {
    final enviadas = <String>[];
    await procesarCola([inicie, termine], (a) async {
      enviadas.add(a.estado);
      return ResultadoEnvio.sinConexion;
    });
    expect(enviadas, ['en_curso']);
  });

  test('si el servidor la rechaza (viaje cancelado) se descarta y sigue', () async {
    final r = await procesarCola([llegue, inicie], (a) async =>
        a.estado == 'conductor_llego' ? ResultadoEnvio.descartado : ResultadoEnvio.enviado);
    expect(r.descartadas.single.estado, 'conductor_llego');
    expect(r.pendientes, isEmpty);
  });

  test('se guarda y se recupera igual (JSON)', () {
    final copia = AccionPendiente.fromJson(termine.toJson());
    expect(copia.viajeId, 'v1');
    expect(copia.estado, 'completado');
    expect(copia.ocurridoEn.toUtc(), termine.ocurridoEn.toUtc());
  });
}
