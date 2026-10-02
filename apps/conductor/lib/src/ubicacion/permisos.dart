import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAvisoAceptado = 'aviso_ubicacion_aceptado';

/// Pide lo necesario para compartir la ubicación. Devuelve null si todo está
/// listo, o un mensaje para el conductor si falta algo.
///
/// Antes de pedir el permiso por primera vez se muestra un aviso que explica
/// para qué se usa la ubicación (Google Play lo exige: "divulgación destacada").
Future<String?> prepararUbicacion(BuildContext context) async {
  final prefs = SharedPreferencesAsync();
  if (await prefs.getBool(_kAvisoAceptado) != true) {
    if (!context.mounted) return 'Cancelado';
    final acepta = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AvisoUbicacion(),
    );
    if (acepta != true) return 'Sin tu ubicación no podemos enviarte viajes cercanos.';
    await prefs.setBool(_kAvisoAceptado, true);
  }

  if (!await Geolocator.isLocationServiceEnabled()) {
    await Geolocator.openLocationSettings();
    return 'Activa la ubicación (GPS) del teléfono y vuelve a intentarlo.';
  }

  var permiso = await Geolocator.checkPermission();
  if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
  if (permiso == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
    return 'Permite la ubicación en los ajustes de la app (Permisos → Ubicación).';
  }
  if (permiso == LocationPermission.denied) {
    return 'Sin permiso de ubicación no podemos enviarte viajes cercanos.';
  }

  // Android 13+: permiso para mostrar la notificación de "En servicio".
  // Si lo niega, el servicio funciona igual (solo no se ve el aviso).
  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  return null;
}

class _AvisoUbicacion extends StatelessWidget {
  const _AvisoUbicacion();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tu ubicación'),
      content: const SingleChildScrollView(
        child: Text(
          'Mientras estés DISPONIBLE u OCUPADO, la app comparte tu ubicación cada pocos '
          'segundos, también con la pantalla apagada o la app cerrada, para:\n\n'
          '• ofrecerte los viajes más cercanos, y\n'
          '• que el pasajero vea llegar tu taxi.\n\n'
          'Verás un aviso fijo "Estás en servicio" mientras esto pase.\n\n'
          'Cuando sales de servicio, la app deja de usar tu ubicación y se borra la última '
          'que teníamos.',
          style: TextStyle(fontSize: 18),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(120, 52)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}
