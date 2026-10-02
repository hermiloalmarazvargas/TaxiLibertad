import 'package:conductor/src/sesion/pantalla_login.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_core/taxi_core.dart';

Widget _app() => ProviderScope(
      child: MaterialApp(theme: temaTaxi(), home: const PantallaLogin()),
    );

void main() {
  testWidgets('pide usuario y contraseña antes de intentar entrar', (tester) async {
    await tester.pumpWidget(_app());

    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Escribe tu usuario'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  testWidgets('el botón Entrar es grande (mínimo 64 px de alto)', (tester) async {
    await tester.pumpWidget(_app());
    final alto = tester.getSize(find.widgetWithText(FilledButton, 'Entrar')).height;
    expect(alto, greaterThanOrEqualTo(64));
  });

  testWidgets('se puede ver la contraseña para revisar lo escrito', (tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'clave1234');

    EditableText campo() => tester.widget<EditableText>(
          find.descendant(of: find.widgetWithText(TextFormField, 'Contraseña'), matching: find.byType(EditableText)),
        );
    expect(campo().obscureText, isTrue);
    await tester.tap(find.byTooltip('Ver contraseña'));
    await tester.pump();
    expect(campo().obscureText, isFalse);
  });
}
