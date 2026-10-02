import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';

import 'avisos.dart';
import 'datos_viaje.dart';

/// Oferta a pantalla completa: botones enormes y cuenta regresiva.
/// Devuelve true si el conductor aceptó y el viaje quedó asignado.
class PantallaOferta extends ConsumerStatefulWidget {
  const PantallaOferta({super.key, required this.oferta});

  final Oferta oferta;

  @override
  ConsumerState<PantallaOferta> createState() => _PantallaOfertaState();
}

class _PantallaOfertaState extends ConsumerState<PantallaOferta> {
  late final DateTime _vence;
  late final Timer _reloj;
  int _restantes = 0;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Los segundos vienen del servidor; se cuentan desde que llegó la oferta.
    _restantes = widget.oferta.segundosRestantes;
    _vence = DateTime.now().add(Duration(seconds: _restantes));
    _reloj = Timer.periodic(const Duration(milliseconds: 250), (_) => _tic());
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _reloj.cancel();
    AvisosOferta.quitar();
    super.dispose();
  }

  void _tic() {
    final restantes = _vence.difference(DateTime.now()).inMilliseconds;
    final segundos = (restantes / 1000).ceil().clamp(0, 999);
    if (segundos != _restantes) setState(() => _restantes = segundos);
    if (restantes <= 0 && !_enviando) {
      _reloj.cancel();
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _responder(bool aceptar) async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('responder_oferta', params: {
        'p_oferta_id': widget.oferta.id,
        'p_aceptar': aceptar,
      });
      if (mounted) Navigator.of(context).pop(aceptar);
    } catch (e) {
      if (!mounted) return;
      if (codigoDeError(e) == 'oferta_vencida') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            content: const Text('La oferta ya no está disponible.', style: TextStyle(fontSize: 20)),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
          ),
        );
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _enviando = false;
        _error = mensajeDeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.oferta;
    final texto = Theme.of(context).textTheme;
    final total = o.segundosRestantes == 0 ? 1 : o.segundosRestantes;

    return PopScope(
      // Volver atrás no rechaza: la oferta sigue hasta que venza.
      canPop: false,
      child: Scaffold(
        backgroundColor: ColoresTaxi.tinta,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Nuevo viaje',
                          style: texto.headlineMedium?.copyWith(color: Colors.white)),
                    ),
                    Semantics(
                      label: 'Quedan $_restantes segundos',
                      child: Text('$_restantes s',
                          style: texto.headlineMedium?.copyWith(color: ColoresTaxi.ambar)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _restantes / total,
                    minHeight: 12,
                    color: ColoresTaxi.ambar,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: ListView(
                      children: [
                        Text(textoTarifa(o.tarifa), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900)),
                        if (o.distanciaM != null)
                          Text('A ${textoDistancia(o.distanciaM!)} de ti', style: texto.titleLarge),
                        const Divider(height: 32),
                        Text('Recoger en', style: texto.bodyMedium?.copyWith(color: ColoresTaxi.gris)),
                        Text(o.origenReferencia ?? 'Sin referencia (ver en el mapa)', style: texto.titleLarge),
                        if (o.zonaOrigen != null) Text(o.zonaOrigen!, style: texto.bodyLarge),
                        const SizedBox(height: 16),
                        Text('Destino', style: texto.bodyMedium?.copyWith(color: ColoresTaxi.gris)),
                        Text(
                          o.destinoReferencia ?? o.zonaDestino ?? 'No indicado',
                          style: texto.titleLarge,
                        ),
                        if (o.destinoReferencia != null && o.zonaDestino != null)
                          Text(o.zonaDestino!, style: texto.bodyLarge),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                MensajeError(_error),
                if (_error != null) const SizedBox(height: 12),
                SizedBox(
                  height: 96,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ColoresTaxi.verde,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                    ),
                    onPressed: _enviando ? null : () => _responder(true),
                    child: Text(_enviando ? 'Un momento…' : 'ACEPTAR'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54, width: 2),
                  ),
                  onPressed: _enviando ? null : () => _responder(false),
                  child: const Text('Rechazar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
