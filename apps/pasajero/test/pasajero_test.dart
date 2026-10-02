import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pasajero/src/datos.dart';
import 'package:pasajero/src/formato.dart';
import 'package:pasajero/src/pedir/solicitud.dart';
import 'package:pasajero/src/registro/pantalla_registro.dart';
import 'package:taxi_core/taxi_core.dart';

void main() {
  group('registro', () {
    Widget app() => ProviderScope(child: MaterialApp(theme: temaTaxi(), home: const PantallaRegistro()));

    testWidgets('pide nombre y teléfono antes de registrar', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('Empezar'));
      await tester.pump();
      expect(find.text('Escribe tu nombre'), findsOneWidget);
      expect(find.text('Escribe tu teléfono a 10 dígitos'), findsOneWidget);
    });

    testWidgets('acepta el teléfono con espacios o con +52', (tester) async {
      await tester.pumpWidget(app());
      final telefono = find.widgetWithText(TextFormField, 'Tu teléfono');
      for (final valido in ['951 123 4567', '+52 951 123 4567']) {
        await tester.enterText(telefono, valido);
        await tester.tap(find.text('Empezar'));
        await tester.pump();
        expect(find.text('Escribe tu teléfono a 10 dígitos'), findsNothing, reason: valido);
      }
      await tester.enterText(telefono, '951 123');
      await tester.tap(find.text('Empezar'));
      await tester.pump();
      expect(find.text('Escribe tu teléfono a 10 dígitos'), findsOneWidget);
    });
  });

  group('solicitud guardada sin señal', () {
    test('se recupera igual, con el mismo identificador (no se duplica el viaje)', () {
      final original = Solicitud(
        id: 'b0a2c1d4-0000-4000-8000-000000000001',
        origen: const LatLng(16.329, -96.596),
        origenReferencia: 'Frente a la iglesia',
        destino: const LatLng(16.34, -96.596),
      );
      final copia = Solicitud.fromJson(jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(copia.id, original.id);
      expect(copia.origen, original.origen);
      expect(copia.origenReferencia, 'Frente a la iglesia');
      expect(copia.destino, original.destino);
    });

    test('sin destino', () {
      final s = Solicitud(id: 'x', origen: const LatLng(16, -96));
      expect(Solicitud.fromJson(s.toJson()).destino, isNull);
    });
  });

  test('texto de la tarifa', () {
    expect(textoTarifa(45), r'$45');
    expect(textoTarifa(42.5), r'$42.50');
    expect(textoTarifa(null), 'A convenir');
  });

  group('formato', () {
    test('fecha corta en español, con a. m. / p. m.', () {
      expect(fechaCorta(DateTime(2026, 10, 1, 20, 5)), 'jue 1 oct, 8:05 p. m.');
      expect(fechaCorta(DateTime(2026, 10, 4, 0, 30)), 'dom 4 oct, 12:30 a. m.');
      expect(fechaCorta(DateTime(2026, 10, 5, 12, 0)), 'lun 5 oct, 12:00 p. m.');
    });

    test('teléfono legible', () {
      expect(telefonoLegible('+529511234567'), '951 123 4567');
      expect(telefonoLegible(null), '');
    });

    test('estado del viaje en palabras', () {
      expect(textoEstado('sin_conductor'), 'Sin taxi disponible');
      expect(textoEstado('completado'), 'Completado');
    });
  });
}
