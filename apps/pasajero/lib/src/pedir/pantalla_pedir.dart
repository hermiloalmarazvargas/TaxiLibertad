import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:taxi_core/taxi_core.dart';

import '../datos.dart';
import 'solicitud.dart';

enum _Paso { origen, destino, confirmar }

/// Pedir un taxi en 3 pasos: dónde te recogemos → a dónde vas (opcional) →
/// confirmar con la tarifa. El pasajero mueve el MAPA bajo un pin fijo
/// (más fácil que tocar un punto exacto con el dedo).
class PantallaPedir extends ConsumerStatefulWidget {
  const PantallaPedir({super.key});

  @override
  ConsumerState<PantallaPedir> createState() => _PantallaPedirState();
}

class _PantallaPedirState extends ConsumerState<PantallaPedir> {
  final _mapa = MapController();
  final _refOrigen = TextEditingController();
  final _refDestino = TextEditingController();
  var _paso = _Paso.origen;
  var _estilo = EstiloMapa.calles;
  LatLng _centro = centroMiahuatlan;
  LatLng? _origen;
  LatLng? _destino;
  Future<Tarifa>? _tarifa;

  @override
  void initState() {
    super.initState();
    _irAMiUbicacion(silencioso: true);
  }

  @override
  void dispose() {
    _refOrigen.dispose();
    _refDestino.dispose();
    super.dispose();
  }

  /// Centra el mapa donde está el teléfono (si hay permiso y GPS).
  Future<void> _irAMiUbicacion({bool silencioso = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silencioso) _avisar('Activa la ubicación del teléfono, o mueve el mapa a mano.');
        return;
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        if (!silencioso) _avisar('Sin permiso de ubicación: mueve el mapa hasta donde estás.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      _centro = LatLng(p.latitude, p.longitude);
      // Sin key de mapa no hay mapa que mover, pero el punto sí se usa.
      if (mounted && hayKeyDeMapa) _mapa.move(_centro, 17);
    } catch (_) {
      if (!silencioso) _avisar('No pudimos leer tu ubicación. Mueve el mapa hasta donde estás.');
    }
  }

  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto, style: const TextStyle(fontSize: 17))));
  }

  void _siguiente() {
    setState(() {
      switch (_paso) {
        case _Paso.origen:
          _origen = _centro;
          _paso = _Paso.destino;
        case _Paso.destino:
          _destino = _centro;
          _confirmar();
        case _Paso.confirmar:
          break;
      }
    });
  }

  void _sinDestino() => setState(() {
        _destino = null;
        _confirmar();
      });

  void _confirmar() {
    _paso = _Paso.confirmar;
    _tarifa = tarifaEstimada(ref, _origen!, _destino);
  }

  void _atras() => setState(() {
        if (_paso == _Paso.confirmar) {
          _paso = _Paso.destino;
          if (_destino != null && hayKeyDeMapa) _mapa.move(_destino!, _mapa.camera.zoom);
        } else if (_paso == _Paso.destino) {
          _paso = _Paso.origen;
          if (hayKeyDeMapa) _mapa.move(_origen!, _mapa.camera.zoom);
        }
      });

  void _pedir() {
    ref.read(envioSolicitudProvider.notifier).pedir(Solicitud(
          id: nuevoUuid(),
          origen: _origen!,
          origenReferencia: _refOrigen.text.trim().isEmpty ? null : _refOrigen.text.trim(),
          destino: _destino,
          destinoReferencia: _refDestino.text.trim().isEmpty ? null : _refDestino.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final envio = ref.watch(envioSolicitudProvider);
    final texto = Theme.of(context).textTheme;
    final pin = switch (_paso) {
      _Paso.origen => (Icons.person_pin_circle, ColoresTaxi.tinta),
      _Paso.destino => (Icons.flag_circle, ColoresTaxi.rojo),
      _Paso.confirmar => null,
    };

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              if (!hayKeyDeMapa)
                const AvisoSinMapa()
              else
                FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCenter: centroMiahuatlan,
                    initialZoom: 15,
                    onPositionChanged: (camara, _) => _centro = camara.center,
                  ),
                  children: [
                    ...capasBaseMapa(estilo: _estilo, paquete: 'mx.taximiahuatlan.pasajero'),
                    MarkerLayer(markers: [
                      if (_origen != null && _paso != _Paso.origen)
                        Marker(
                          point: _origen!,
                          width: 48,
                          height: 48,
                          alignment: Alignment.topCenter,
                          child: const Icon(Icons.person_pin_circle, size: 48, color: ColoresTaxi.tinta),
                        ),
                      if (_destino != null && _paso == _Paso.confirmar)
                        Marker(
                          point: _destino!,
                          width: 48,
                          height: 48,
                          alignment: Alignment.topCenter,
                          child: const Icon(Icons.flag_circle, size: 48, color: ColoresTaxi.rojo),
                        ),
                    ]),
                  ],
                ),
              // Pin fijo al centro: la punta marca el lugar exacto.
              if (pin != null)
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 56),
                      child: Icon(pin.$1, size: 56, color: pin.$2),
                    ),
                  ),
                ),
              Positioned(
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    _BotonMapa(
                      icono: _estilo == EstiloMapa.calles ? Icons.satellite_alt : Icons.map,
                      tooltip: _estilo == EstiloMapa.calles ? 'Ver satélite' : 'Ver calles',
                      onPressed: () => setState(() =>
                          _estilo = _estilo == EstiloMapa.calles ? EstiloMapa.satelite : EstiloMapa.calles),
                    ),
                    const SizedBox(height: 8),
                    _BotonMapa(icono: Icons.my_location, tooltip: 'Mi ubicación', onPressed: _irAMiUbicacion),
                  ],
                ),
              ),
            ],
          ),
        ),
        Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: switch (envio) {
              Enviando() => const _Aviso(texto: 'Pidiendo tu taxi…', cargando: true),
              EsperandoSenal() => const _Aviso(
                  texto: 'Sin señal. Tu pedido se enviará solo en cuanto haya conexión.',
                  cargando: true,
                ),
              _ => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (envio is EnvioRechazado) ...[
                      MensajeError(envio.mensaje),
                      const SizedBox(height: 12),
                    ],
                    ...switch (_paso) {
                      _Paso.origen => [
                          Text('¿Dónde te recogemos?', style: texto.titleLarge),
                          Text('Mueve el mapa hasta que el pin quede en tu puerta.', style: texto.bodyMedium),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _refOrigen,
                            decoration: const InputDecoration(
                              labelText: 'Referencia (opcional)',
                              hintText: 'Ej.: frente a la iglesia, portón verde',
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _siguiente, child: const Text('Aquí me recogen')),
                        ],
                      _Paso.destino => [
                          Text('¿A dónde vas?', style: texto.titleLarge),
                          Text('Mueve el mapa a tu destino. Es opcional: sirve para saber la tarifa.',
                              style: texto.bodyMedium),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _siguiente, child: const Text('Voy aquí')),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(child: OutlinedButton(onPressed: _atras, child: const Text('Atrás'))),
                            const SizedBox(width: 8),
                            Expanded(child: OutlinedButton(onPressed: _sinDestino, child: const Text('No sé'))),
                          ]),
                        ],
                      _Paso.confirmar => [
                          _ResumenTarifa(tarifa: _tarifa!),
                          if (_destino != null) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _refDestino,
                              decoration: const InputDecoration(labelText: 'Referencia del destino (opcional)'),
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 80,
                            child: FilledButton(
                              style: FilledButton.styleFrom(textStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                              onPressed: _pedir,
                              child: const Text('PEDIR TAXI'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(onPressed: _atras, child: const Text('Atrás')),
                        ],
                    },
                  ],
                ),
            },
          ),
        ),
      ],
    );
  }
}

class _ResumenTarifa extends StatelessWidget {
  const _ResumenTarifa({required this.tarifa});

  final Future<Tarifa> tarifa;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return FutureBuilder<Tarifa>(
      future: tarifa,
      builder: (context, s) {
        if (s.hasError) return MensajeError(mensajeDeError(s.error!));
        final t = s.data;
        if (t == null) return const _Aviso(texto: 'Calculando tarifa…', cargando: true);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tarifa', style: texto.bodyMedium?.copyWith(color: ColoresTaxi.gris)),
            Text(textoTarifa(t.monto), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
            if (t.monto == null)
              Text('Ponte de acuerdo con el taxista.', style: texto.bodyLarge)
            else if ((t.recargo ?? 0) > 0)
              Text('Incluye ${textoTarifa(t.recargo)} de recargo nocturno.', style: texto.bodyLarge),
            if (t.monto == null && t.nocturno) Text('Es horario nocturno.', style: texto.bodyLarge),
            Text('Pagas en efectivo al taxista.', style: texto.bodyMedium),
          ],
        );
      },
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, this.cargando = false});

  final String texto;
  final bool cargando;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            if (cargando) ...[const CircularProgressIndicator(), const SizedBox(width: 16)],
            Expanded(child: Text(texto, style: Theme.of(context).textTheme.titleLarge)),
          ],
        ),
      );
}

class _BotonMapa extends StatelessWidget {
  const _BotonMapa({required this.icono, required this.tooltip, required this.onPressed});

  final IconData icono;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        child: IconButton(iconSize: 30, tooltip: tooltip, icon: Icon(icono), onPressed: onPressed),
      );
}
