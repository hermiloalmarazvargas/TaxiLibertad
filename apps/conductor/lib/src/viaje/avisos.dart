import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'datos_viaje.dart';

/// Notificación con sonido y vibración cuando llega una oferta, para que el
/// conductor se entere aunque tenga la pantalla apagada o esté en otra app.
/// Al tocarla se abre la app y la oferta aparece en pantalla completa.
///
/// Limitación: requiere que la app siga viva en segundo plano (el servicio de
/// ubicación la mantiene así). Si Android la cierra del todo, el aviso llegará
/// por notificaciones push (fase 5).
abstract final class AvisosOferta {
  static const _canal = 'ofertas';
  static const _id = 7101;
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> configurar() async {
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _canal,
          'Ofertas de viaje',
          description: 'Suena cuando te ofrecen un viaje',
          importance: Importance.max, // aparece arriba de la pantalla, con sonido
        ));
  }

  static Future<void> mostrar(Oferta oferta) => _plugin.show(
        id: _id,
        title: '🚕 Nuevo viaje · ${textoTarifa(oferta.tarifa)}',
        body: [
          oferta.origenReferencia ?? 'Sin referencia',
          if (oferta.zonaOrigen != null) oferta.zonaOrigen!,
          if (oferta.distanciaM != null) 'a ${textoDistancia(oferta.distanciaM!)}',
        ].join(' · '),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _canal,
            'Ofertas de viaje',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            visibility: NotificationVisibility.public,
            // La oferta dura 20 s: después ya no sirve.
            timeoutAfter: 20000,
          ),
        ),
      );

  static Future<void> quitar() => _plugin.cancel(id: _id);
}
