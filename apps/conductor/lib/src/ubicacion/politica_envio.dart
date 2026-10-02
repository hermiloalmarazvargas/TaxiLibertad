import 'dart:math' as math;

/// Cuándo vale la pena mandar la ubicación al servidor.
///
/// · Si se movió más de [metrosMinimos] → enviar (como máximo cada tick, ~5 s).
/// · Si está parado → enviar de todos modos cada [maximoSinEnviar], para que
///   el servidor no lo considere "sin señal" (el límite allá es 60 s) sin
///   gastar datos de más.
class PoliticaEnvio {
  const PoliticaEnvio({
    this.metrosMinimos = 10,
    this.maximoSinEnviar = const Duration(seconds: 20),
  });

  final double metrosMinimos;
  final Duration maximoSinEnviar;

  bool debeEnviar({
    required ({double lat, double lng})? ultimaEnviada,
    required DateTime? enviadaEn,
    required ({double lat, double lng}) actual,
    required DateTime ahora,
  }) {
    if (ultimaEnviada == null || enviadaEn == null) return true;
    if (ahora.difference(enviadaEn) >= maximoSinEnviar) return true;
    return metrosEntre(ultimaEnviada, actual) >= metrosMinimos;
  }
}

/// Distancia en línea recta (fórmula del haversine), en metros.
double metrosEntre(({double lat, double lng}) a, ({double lat, double lng}) b) {
  const radioTierra = 6371000.0;
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * radioTierra * math.asin(math.sqrt(h));
}
