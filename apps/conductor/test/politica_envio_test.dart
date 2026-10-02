import 'package:conductor/src/ubicacion/politica_envio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const politica = PoliticaEnvio();
  final t0 = DateTime(2026, 10, 1, 12);
  const centro = (lat: 16.3290, lng: -96.5960);

  test('la primera ubicación siempre se envía', () {
    expect(politica.debeEnviar(ultimaEnviada: null, enviadaEn: null, actual: centro, ahora: t0), isTrue);
  });

  test('parado: no se reenvía antes de 20 s', () {
    expect(
      politica.debeEnviar(ultimaEnviada: centro, enviadaEn: t0, actual: centro, ahora: t0.add(const Duration(seconds: 15))),
      isFalse,
    );
  });

  test('parado: a los 20 s se reenvía para no quedar "sin señal"', () {
    expect(
      politica.debeEnviar(ultimaEnviada: centro, enviadaEn: t0, actual: centro, ahora: t0.add(const Duration(seconds: 20))),
      isTrue,
    );
  });

  test('en movimiento (más de 10 m): se envía aunque no pasen 20 s', () {
    const quinceMetrosAlNorte = (lat: 16.32914, lng: -96.5960);
    expect(metrosEntre(centro, quinceMetrosAlNorte), closeTo(15.6, 0.5));
    expect(
      politica.debeEnviar(
        ultimaEnviada: centro, enviadaEn: t0, actual: quinceMetrosAlNorte, ahora: t0.add(const Duration(seconds: 5))),
      isTrue,
    );
  });

  test('variación del GPS de pocos metros no cuenta como movimiento', () {
    const cincoMetros = (lat: 16.32904, lng: -96.5960);
    expect(
      politica.debeEnviar(ultimaEnviada: centro, enviadaEn: t0, actual: cincoMetros, ahora: t0.add(const Duration(seconds: 5))),
      isFalse,
    );
  });
}
