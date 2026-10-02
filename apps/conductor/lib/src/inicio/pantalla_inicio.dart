import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taxi_core/taxi_core.dart';

import '../ubicacion/permisos.dart';
import '../viaje/avisos.dart';
import '../viaje/cola_acciones.dart';
import '../viaje/datos_viaje.dart';
import '../viaje/pantalla_oferta.dart';
import '../viaje/vista_viaje.dart';
import '../ubicacion/servicio_ubicacion.dart';
import 'datos.dart';

class PantallaInicio extends ConsumerStatefulWidget {
  const PantallaInicio({super.key});

  @override
  ConsumerState<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends ConsumerState<PantallaInicio> with WidgetsBindingObserver {
  RealtimeChannel? _canal;
  int? _ofertaAbierta;
  StreamSubscription<AuthState>? _sesion;
  int? _unidadElegida;
  bool _trabajando = false;
  String? _error;

  SupabaseClient get _supabase => ref.read(supabaseProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ultimaUnidad().then((id) {
      if (mounted && _unidadElegida == null) setState(() => _unidadElegida = id);
    });
    _escucharCambios();
    // El servicio de ubicación no renueva la sesión: se le pasa cada token nuevo.
    _sesion = _supabase.auth.onAuthStateChange.listen((cambio) {
      final token = cambio.session?.accessToken;
      if (cambio.event == AuthChangeEvent.tokenRefreshed && token != null) {
        ServicioUbicacion.actualizarToken(token);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sesion?.cancel();
    final canal = _canal;
    if (canal != null) _supabase.removeChannel(canal);
    super.dispose();
  }

  /// Al volver a la app (p. ej. tocando la notificación de una oferta) se
  /// revisa todo, por si algo cambió mientras estaba en segundo plano.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado != AppLifecycleState.resumed) return;
    ref.invalidate(datosConductorProvider);
    ref.invalidate(viajeActivoProvider);
    ref.read(colaAccionesProvider.notifier).procesar();
    _revisarOferta();
  }

  /// Cambios hechos por el servidor (p. ej. lo sacaron de servicio por no
  /// responder ofertas) y avisos para el conductor, en vivo.
  void _escucharCambios() {
    final uid = _supabase.auth.currentUser!.id;
    PostgresChangeFilter delConductor(String columna) =>
        PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: columna, value: uid);

    _canal = _supabase
        .channel('conductor-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conductor_estado',
          filter: delConductor('conductor_id'),
          callback: (_) => ref.invalidate(datosConductorProvider),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificaciones',
          filter: delConductor('perfil_id'),
          callback: (_) => _mostrarAvisosPendientes(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ofertas_viaje',
          filter: delConductor('conductor_id'),
          callback: (_) => _revisarOferta(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'viajes',
          filter: delConductor('conductor_id'),
          callback: (_) => ref.invalidate(viajeActivoProvider),
        )
        .subscribe((estado, _) {
      // Al (re)conectar, ponerse al día con lo que pasó sin señal.
      if (estado == RealtimeSubscribeStatus.subscribed) {
        ref.invalidate(datosConductorProvider);
        ref.invalidate(viajeActivoProvider);
        _mostrarAvisosPendientes();
        _revisarOferta();
      }
    });
  }

  /// Si hay una oferta pendiente, suena el aviso y se muestra a pantalla completa.
  Future<void> _revisarOferta() async {
    ref.invalidate(ofertaPendienteProvider);
    final oferta = await ref.read(ofertaPendienteProvider.future).catchError((_) => null);
    if (oferta == null || oferta.id == _ofertaAbierta || !mounted) return;
    _ofertaAbierta = oferta.id;
    await AvisosOferta.mostrar(oferta);
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PantallaOferta(oferta: oferta)),
    );
    _ofertaAbierta = null;
    ref.invalidate(viajeActivoProvider);
    ref.invalidate(datosConductorProvider);
  }

  /// Si el viaje desaparece sin que el conductor lo haya terminado, es que
  /// el pasajero o el despacho lo cancelaron.
  void _avisarSiCancelaron(ViajeActivo? antes, ViajeActivo? ahora) {
    if (antes == null || ahora != null) return;
    final cola = ref.read(colaAccionesProvider.notifier);
    final terminado = cola.estadoPendiente(antes.id) == 'completado' || antes.estado == 'en_curso';
    if (terminado || cola.fueSoltado(antes.id) || !mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Viaje cancelado'),
        content: Text(
          '${antes.pasajeroNombre ?? "El pasajero"} ya no necesita el taxi. Sigues en servicio.',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  Future<void> _mostrarAvisosPendientes() async {
    final avisos = await _supabase
        .from('notificaciones')
        .select('id, titulo, cuerpo')
        .isFilter('leida_en', null)
        .order('creada_en')
        .catchError((_) => <Map<String, dynamic>>[]);
    for (final aviso in avisos) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(aviso['titulo'] as String),
          content: Text(aviso['cuerpo'] as String, style: const TextStyle(fontSize: 18)),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
        ),
      );
      await _supabase
          .from('notificaciones')
          .update({'leida_en': DateTime.now().toUtc().toIso8601String()})
          .eq('id', aviso['id'] as Object);
    }
  }

  /// El servicio de ubicación sigue lo que dice el servidor: en servicio →
  /// corriendo; fuera de servicio → detenido.
  void _sincronizarServicio(DatosConductor datos) {
    final token = _supabase.auth.currentSession?.accessToken;
    if (datos.enServicio && token != null) {
      ServicioUbicacion.iniciar(token: token, conductorId: datos.id);
    } else if (!datos.enServicio) {
      ServicioUbicacion.detener();
    }
  }

  Future<void> _cambiarEstado(String estado, {int? unidadId}) async {
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      if (estado != 'fuera_de_servicio') {
        final falta = await prepararUbicacion(context);
        if (falta != null) {
          setState(() => _error = falta);
          return;
        }
      }
      await _supabase.rpc('cambiar_disponibilidad', params: {
        'p_estado': estado,
        'p_unidad_id': ?unidadId,
      });
      if (unidadId != null) await recordarUnidad(unidadId);
      ref.invalidate(datosConductorProvider);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _confirmarSalida(DatosConductor? datos) async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: Text(
          datos?.enServicio == true
              ? 'Saldrás de servicio y tendrás que volver a escribir tu usuario y contraseña.'
              : 'Tendrás que volver a escribir tu usuario y contraseña.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sí, salir')),
        ],
      ),
    );
    if (salir != true) return;
    try {
      // Primero salir de servicio: si no, seguiría recibiendo ofertas.
      if (datos?.enServicio == true) {
        await _supabase.rpc('cambiar_disponibilidad', params: {'p_estado': 'fuera_de_servicio'});
      }
      await ServicioUbicacion.detener();
      await _supabase.auth.signOut();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(datosConductorProvider, (_, siguiente) {
      final datos = siguiente.value;
      if (datos != null) _sincronizarServicio(datos);
    });
    ref.listen(viajeActivoProvider, (antes, ahora) {
      if (antes?.hasValue == true && ahora.hasValue) _avisarSiCancelaron(antes!.value, ahora.value);
    });
    // Mantiene viva la cola de pasos sin enviar (reintenta sola).
    ref.watch(colaAccionesProvider);
    final datos = ref.watch(datosConductorProvider);
    final viaje = ref.watch(viajeActivoProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Taxi Miahuatlán'),
        actions: [
          IconButton(
            iconSize: 30,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmarSalida(datos.value),
          ),
        ],
      ),
      body: Column(
        children: [
          const BannerConexion(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(unidadesProvider);
                ref.invalidate(viajeActivoProvider);
                ref.invalidate(datosConductorProvider);
                await ref.read(datosConductorProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  datos.when(
                    data: (d) => viaje != null ? VistaViaje(viaje: viaje) : _contenido(d),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MensajeError(mensajeDeError(e)),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => ref.invalidate(datosConductorProvider),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido(DatosConductor d) {
    final texto = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Hola, ${d.nombre}', style: texto.headlineMedium),
        Text(d.sitio, style: texto.bodyLarge?.copyWith(color: ColoresTaxi.gris)),
        const SizedBox(height: 20),
        _TarjetaEstado(datos: d),
        const SizedBox(height: 20),
        MensajeError(_error),
        if (_error != null) const SizedBox(height: 16),
        ...switch (d.estado) {
          'disponible' => [
              OutlinedButton(
                onPressed: _trabajando ? null : () => _cambiarEstado('ocupado'),
                child: const Text('Pausa: estoy ocupado'),
              ),
              const SizedBox(height: 12),
              _BotonSalir(onPressed: _trabajando ? null : () => _cambiarEstado('fuera_de_servicio')),
            ],
          'ocupado' => [
              _BotonVerde(
                texto: 'Volver a estar disponible',
                onPressed: _trabajando ? null : () => _cambiarEstado('disponible'),
              ),
              const SizedBox(height: 12),
              _BotonSalir(onPressed: _trabajando ? null : () => _cambiarEstado('fuera_de_servicio')),
            ],
          _ => [
              _SelectorUnidad(
                elegida: _unidadElegida,
                onElegir: (id) => setState(() => _unidadElegida = id),
              ),
              const SizedBox(height: 16),
              _BotonVerde(
                texto: _trabajando ? 'Un momento…' : 'Ponerme disponible',
                onPressed: _trabajando || _unidadElegida == null
                    ? null
                    : () => _cambiarEstado('disponible', unidadId: _unidadElegida),
              ),
            ],
        },
      ],
    );
  }
}

class _TarjetaEstado extends StatelessWidget {
  const _TarjetaEstado({required this.datos});

  final DatosConductor datos;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final (color, etiqueta, detalle) = switch (datos.estado) {
      'disponible' => (ColoresTaxi.verde, 'Disponible', 'Esperando viajes. Puedes apagar la pantalla.'),
      'ocupado' => (ColoresTaxi.ambar, 'Ocupado', 'No recibirás viajes nuevos.'),
      _ => (
          ColoresTaxi.gris,
          'Fuera de servicio',
          datos.motivoFuera == 'sin_respuesta'
              ? 'Saliste de servicio porque no respondiste 3 ofertas seguidas.'
              : 'Elige tu unidad y ponte disponible para recibir viajes.',
        ),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tu estado', style: texto.bodyMedium),
            Text(etiqueta, style: texto.headlineMedium?.copyWith(color: color)),
            if (datos.enServicio && datos.unidad != null) Text('Unidad ${datos.unidad}', style: texto.titleLarge),
            const SizedBox(height: 8),
            Text(detalle, style: texto.bodyLarge),
            if (datos.enServicio) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.my_location, color: ColoresTaxi.verde),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Compartiendo tu ubicación', style: texto.bodyMedium)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectorUnidad extends ConsumerWidget {
  const _SelectorUnidad({required this.elegida, required this.onElegir});

  final int? elegida;
  final ValueChanged<int> onElegir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unidades = ref.watch(unidadesProvider);
    final texto = Theme.of(context).textTheme;

    return unidades.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => MensajeError(mensajeDeError(e)),
      data: (lista) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('¿Qué unidad vas a manejar?', style: texto.titleLarge),
          const SizedBox(height: 8),
          if (lista.isEmpty) const MensajeError('Tu sitio no tiene unidades activas. Avisa al administrador.'),
          RadioGroup<int>(
            groupValue: elegida,
            onChanged: (id) => onElegir(id!),
            child: Column(
              children: [
                for (final u in lista)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: u.id == elegida ? ColoresTaxi.tinta : const Color(0xFFCBD5E1),
                        width: u.id == elegida ? 3 : 1,
                      ),
                    ),
                    child: RadioListTile<int>(
                      value: u.id,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      title: Text('Unidad ${u.numero}', style: texto.titleLarge),
                      subtitle: Text(
                        [u.placas, if (u.descripcion?.isNotEmpty == true) u.descripcion].join(' · '),
                        style: texto.bodyMedium,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonVerde extends StatelessWidget {
  const _BotonVerde({required this.texto, required this.onPressed});

  final String texto;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: ColoresTaxi.verde, foregroundColor: Colors.white),
      onPressed: onPressed,
      child: Text(texto),
    );
  }
}

class _BotonSalir extends StatelessWidget {
  const _BotonSalir({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: ColoresTaxi.rojo,
        side: const BorderSide(color: ColoresTaxi.rojo, width: 2),
      ),
      onPressed: onPressed,
      child: const Text('Salir de servicio'),
    );
  }
}
