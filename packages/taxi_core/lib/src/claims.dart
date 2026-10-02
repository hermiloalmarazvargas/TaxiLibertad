import 'dart:convert';

/// Datos que el `custom_access_token_hook` agrega al token de sesión.
class Claims {
  const Claims({this.rol, this.sitioId});

  /// 'pasajero' | 'conductor' | 'despachador' | 'admin' (null si no se ha registrado).
  final String? rol;
  final int? sitioId;
}

/// Lee los claims del token. Solo sirve para decidir qué mostrar: la
/// seguridad real la aplica la base de datos (RLS), que valida la firma.
Claims leerClaims(String accessToken) {
  try {
    final partes = accessToken.split('.');
    final json = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
    final mapa = jsonDecode(json) as Map<String, dynamic>;
    return Claims(rol: mapa['rol'] as String?, sitioId: (mapa['sitio_id'] as num?)?.toInt());
  } catch (_) {
    return const Claims();
  }
}
