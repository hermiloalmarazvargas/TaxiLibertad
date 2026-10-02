import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taxi_core/taxi_core.dart';

/// Token de prueba con el payload indicado (la firma no importa para leerlo).
String token(Map<String, dynamic> payload) {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64(payload)}.firma';
}

void main() {
  group('correoDeUsuario', () {
    test('normaliza espacios y mayúsculas', () {
      expect(correoDeUsuario('  Juan.Perez '), 'juan.perez@usuarios.taxi.internal');
    });
  });

  group('leerClaims', () {
    test('lee rol y sitio del token', () {
      final c = leerClaims(token({'sub': 'x', 'rol': 'conductor', 'sitio_id': 3}));
      expect(c.rol, 'conductor');
      expect(c.sitioId, 3);
    });

    test('token sin rol (pasajero sin registrar)', () {
      expect(leerClaims(token({'sub': 'x'})).rol, isNull);
    });

    test('token inválido no truena', () {
      expect(leerClaims('basura').rol, isNull);
    });
  });

  group('errores', () {
    test('credenciales inválidas en español', () {
      expect(
        mensajeDeError(const AuthException('Invalid login credentials')),
        'Usuario o contraseña incorrectos',
      );
    });

    test('mensaje de nuestros hooks se respeta', () {
      const e = AuthException('Tu cuenta está desactivada. Comunícate con el sitio.');
      expect(mensajeDeError(e), e.message);
    });

    test('código de negocio sale del hint', () {
      const e = PostgrestException(message: 'La oferta ya no está disponible', code: 'P0001', hint: 'oferta_vencida');
      expect(codigoDeError(e), 'oferta_vencida');
      expect(mensajeDeError(e), 'La oferta ya no está disponible');
    });

    test('sin permiso', () {
      const e = PostgrestException(message: 'permission denied for table x', code: '42501');
      expect(codigoDeError(e), 'sin_permiso');
      expect(mensajeDeError(e), 'No tienes permiso para esta acción');
    });

    test('falta de señal se reconoce y se explica', () {
      const e = SocketException('Failed host lookup');
      expect(esErrorDeRed(e), isTrue);
      expect(codigoDeError(e), 'sin_conexion');
      expect(mensajeDeError(e), contains('Sin conexión'));
    });
  });

  group('nuevoUuid', () {
    test('formato UUID v4 y sin repetirse', () {
      final ids = List.generate(1000, (_) => nuevoUuid());
      final formato = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(ids.every(formato.hasMatch), isTrue);
      expect(ids.toSet().length, 1000);
    });
  });
}
