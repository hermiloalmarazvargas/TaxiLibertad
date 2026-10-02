import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'config.dart';

/// Centro de Miahuatlán de Porfirio Díaz.
const centroMiahuatlan = LatLng(16.329, -96.596);

enum EstiloMapa { calles, satelite }

/// Mosaicos de MapTiler (los mismos del panel). La vista satelital ayuda a
/// ubicar casas sin dirección formal.
///
/// La key de las apps debe ser distinta a la del panel: la del panel está
/// restringida al dominio web y las apps no mandan ese origen.
List<Widget> capasBaseMapa({EstiloMapa estilo = EstiloMapa.calles, required String paquete}) {
  final key = ConfigTaxi.maptilerKey;
  final url = estilo == EstiloMapa.calles
      ? 'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=$key'
      : 'https://api.maptiler.com/maps/hybrid/256/{z}/{x}/{y}.jpg?key=$key';
  return [
    TileLayer(urlTemplate: url, userAgentPackageName: paquete, maxNativeZoom: 20),
    const RichAttributionWidget(
      attributions: [
        TextSourceAttribution('MapTiler'),
        TextSourceAttribution('OpenStreetMap contributors'),
      ],
    ),
  ];
}

/// Aviso en lugar del mapa si no se configuró la key de MapTiler.
class AvisoSinMapa extends StatelessWidget {
  const AvisoSinMapa({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFFFEF3C7),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Falta MAPTILER_KEY en config/local.json: sin ella no se puede mostrar el mapa.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
}

bool get hayKeyDeMapa => ConfigTaxi.maptilerKey.isNotEmpty;
