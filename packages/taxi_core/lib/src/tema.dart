import 'package:flutter/material.dart';

/// Colores de la marca (los mismos del panel).
abstract final class ColoresTaxi {
  static const ambar = Color(0xFFF59E0B);
  static const tinta = Color(0xFF0F172A);
  static const verde = Color(0xFF15803D);
  static const rojo = Color(0xFFB91C1C);
  static const gris = Color(0xFF475569);
}

/// Tema pensado para usarse en la calle: fondo claro, texto oscuro de alto
/// contraste (legible al sol), letra grande y botones de al menos 64 px de
/// alto para tocarlos sin fallar, incluso manejando o con guantes.
ThemeData temaTaxi() {
  final esquema = ColorScheme.fromSeed(
    seedColor: ColoresTaxi.ambar,
    primary: ColoresTaxi.ambar,
    onPrimary: ColoresTaxi.tinta,
    error: ColoresTaxi.rojo,
    surface: Colors.white,
    onSurface: ColoresTaxi.tinta,
  );

  const tamanoBoton = Size.fromHeight(64);
  const textoBoton = TextStyle(fontSize: 20, fontWeight: FontWeight.w700);
  final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return ThemeData(
    colorScheme: esquema,
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: ColoresTaxi.tinta),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: ColoresTaxi.tinta),
      bodyLarge: TextStyle(fontSize: 19, color: ColoresTaxi.tinta),
      bodyMedium: TextStyle(fontSize: 17, color: ColoresTaxi.tinta),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: tamanoBoton,
        textStyle: textoBoton,
        shape: forma,
        backgroundColor: ColoresTaxi.ambar,
        foregroundColor: ColoresTaxi.tinta,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: tamanoBoton,
        textStyle: textoBoton,
        shape: forma,
        foregroundColor: ColoresTaxi.tinta,
        side: const BorderSide(color: ColoresTaxi.tinta, width: 2),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      labelStyle: const TextStyle(fontSize: 18),
    ),
  );
}
