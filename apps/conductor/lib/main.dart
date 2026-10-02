import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';

import 'src/app.dart';
import 'src/ubicacion/servicio_ubicacion.dart';
import 'src/viaje/avisos.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await iniciarSupabase();
  await AvisosOferta.configurar();
  await ServicioUbicacion.configurar();
  runApp(const ProviderScope(child: AppConductor()));
}
