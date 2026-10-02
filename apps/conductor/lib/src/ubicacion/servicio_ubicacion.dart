import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_core/taxi_core.dart';

import 'politica_envio.dart';

/// Envío de la ubicación del conductor mientras está en servicio, también con
/// la pantalla apagada o la app en segundo plano.
///
/// Corre en un servicio en primer plano de Android (con notificación fija),
/// en un isolate aparte de la interfaz. Decisiones importantes:
///  · El servicio NO renueva la sesión: recibe el token de la app. Si los dos
///    renovaran a la vez, Supabase detectaría el refresh token reutilizado y
///    cerraría la sesión del conductor.
///  · Si el servidor responde que ya no está en servicio (lo sacaron por no
///    responder, lo desactivaron…), el servicio se detiene solo.
///  · Sin señal no se acumula nada: solo importa la última ubicación.
abstract final class ServicioUbicacion {
  static const _canal = 'servicio_taxi';
  static const _idNotificacion = 7001;

  // Claves en el almacenamiento del teléfono (las lee el servicio si Android
  // lo reinicia por su cuenta).
  static const _kToken = 'servicio.token';
  static const _kConductor = 'servicio.conductor';
  static const _kUrl = 'servicio.url';
  static const _kLlave = 'servicio.llave';

  /// Se llama una vez al abrir la app.
  static Future<void> configurar() async {
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _canal,
          'En servicio',
          description: 'Aviso fijo mientras compartes tu ubicación para recibir viajes',
          importance: Importance.low, // sin sonido ni vibración
          playSound: false,
          enableVibration: false,
        ));

    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: alIniciarServicio,
        autoStart: false,
        // Tras reiniciar el teléfono, el conductor debe abrir la app y
        // ponerse disponible de nuevo (así confirma que está trabajando).
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: _canal,
        initialNotificationTitle: 'Taxi Miahuatlán',
        initialNotificationContent: 'Estás en servicio',
        foregroundServiceNotificationId: _idNotificacion,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }

  static Future<void> iniciar({required String token, required String conductorId}) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kConductor, conductorId);
    await prefs.setString(_kUrl, ConfigTaxi.supabaseUrl);
    await prefs.setString(_kLlave, ConfigTaxi.supabasePublishableKey);

    final servicio = FlutterBackgroundService();
    if (!await servicio.isRunning()) await servicio.startService();
    servicio.invoke('token', {'token': token});
  }

  /// La app llama esto cada vez que Supabase renueva el token (≈ cada hora).
  static Future<void> actualizarToken(String token) async {
    await SharedPreferencesAsync().setString(_kToken, token);
    final servicio = FlutterBackgroundService();
    if (await servicio.isRunning()) servicio.invoke('token', {'token': token});
  }

  static Future<void> detener() async {
    final servicio = FlutterBackgroundService();
    if (await servicio.isRunning()) servicio.invoke('detener');
  }

  static Future<bool> estaCorriendo() => FlutterBackgroundService().isRunning();
}

/// Punto de entrada del servicio (otro isolate: no comparte memoria con la app).
@pragma('vm:entry-point')
Future<void> alIniciarServicio(ServiceInstance servicio) async {
  DartPluginRegistrant.ensureInitialized();

  final prefs = SharedPreferencesAsync();
  var token = await prefs.getString(ServicioUbicacion._kToken);
  final conductorId = await prefs.getString(ServicioUbicacion._kConductor);
  final url = await prefs.getString(ServicioUbicacion._kUrl);
  final llave = await prefs.getString(ServicioUbicacion._kLlave);

  const politica = PoliticaEnvio();
  ({double lat, double lng})? ultimaEnviada;
  DateTime? enviadaEn;
  Position? actual;
  StreamSubscription<Position>? posiciones;
  Timer? reloj;
  var enviando = false;

  Future<void> avisar(String texto) async {
    if (servicio is AndroidServiceInstance) {
      await servicio.setForegroundNotificationInfo(title: 'Taxi Miahuatlán', content: texto);
    }
  }

  Future<void> terminar() async {
    reloj?.cancel();
    await posiciones?.cancel();
    servicio.invoke('detenido');
    await servicio.stopSelf();
  }

  servicio.on('token').listen((datos) => token = datos?['token'] as String? ?? token);
  servicio.on('detener').listen((_) => terminar());

  if (conductorId == null || url == null || llave == null) {
    await terminar();
    return;
  }

  posiciones = Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      intervalDuration: const Duration(seconds: 5),
    ),
  ).listen(
    (p) => actual = p,
    onError: (Object _) => avisar('No se puede leer el GPS. Revisa que la ubicación esté activada.'),
  );

  Future<void> quizasEnviar() async {
    final p = actual;
    if (p == null || enviando || token == null) return;
    final punto = (lat: p.latitude, lng: p.longitude);
    final ahora = DateTime.now();
    if (!politica.debeEnviar(ultimaEnviada: ultimaEnviada, enviadaEn: enviadaEn, actual: punto, ahora: ahora)) {
      return;
    }

    enviando = true;
    try {
      final respuesta = await http
          .patch(
            Uri.parse('$url/rest/v1/conductor_estado?conductor_id=eq.$conductorId&select=estado'),
            headers: {
              'apikey': llave,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              // Devuelve la fila: si viene vacía, RLS no dejó actualizar
              // porque el conductor ya no está en servicio.
              'Prefer': 'return=representation',
            },
            body: jsonEncode({
              // PostGIS: longitud primero.
              'ubicacion': 'SRID=4326;POINT(${p.longitude} ${p.latitude})',
              'rumbo': p.heading >= 0 && p.heading < 360 ? p.heading.round() % 360 : null,
              'precision_m': p.accuracy,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (respuesta.statusCode == 200 && (jsonDecode(respuesta.body) as List).isEmpty) {
        await avisar('Ya no estás en servicio.');
        await terminar();
        return;
      }
      if (respuesta.statusCode == 401) {
        await avisar('Abre la app para seguir recibiendo viajes.');
        return;
      }
      if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) {
        ultimaEnviada = punto;
        enviadaEn = ahora;
        final hora = '${ahora.hour}:${ahora.minute.toString().padLeft(2, '0')}';
        await avisar('Estás en servicio · ubicación enviada $hora');
      }
    } catch (_) {
      // Sin señal: se reintenta en el siguiente ciclo con la ubicación más nueva.
      await avisar('Sin señal. Seguimos intentando…');
    } finally {
      enviando = false;
    }
  }

  reloj = Timer.periodic(const Duration(seconds: 5), (_) => quizasEnviar());
}
