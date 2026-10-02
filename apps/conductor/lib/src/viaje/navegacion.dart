import 'package:url_launcher/url_launcher.dart';

/// La ruta la calcula Google Maps o Waze (más confiables que una ruta propia
/// y ya instalados en casi todos los teléfonos).
Future<bool> abrirGoogleMaps(double lat, double lng) => launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
      mode: LaunchMode.externalApplication,
    );

Future<bool> abrirWaze(double lat, double lng) => launchUrl(
      Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes'),
      mode: LaunchMode.externalApplication,
    );

Future<bool> llamar(String telefono) => launchUrl(Uri(scheme: 'tel', path: telefono));
