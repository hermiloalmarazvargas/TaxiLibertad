import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Código estable de un error de negocio (lo que la base manda en `hint`,
/// p. ej. 'oferta_vencida', 'unidad_ocupada'). La app decide qué hacer con
/// este código, nunca comparando el texto del mensaje.
String? codigoDeError(Object error) {
  if (error is PostgrestException) {
    final hint = error.hint;
    if (hint != null && hint.isNotEmpty) return hint;
    if (error.code == '42501') return 'sin_permiso';
  }
  if (esErrorDeRed(error)) return 'sin_conexion';
  return null;
}

/// Si el error se debe a falta de señal (conviene reintentar más tarde).
bool esErrorDeRed(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    (error is AuthRetryableFetchException) ||
    (error is PostgrestException && error.message.contains('SocketException'));

/// Mensaje en español para mostrar al usuario.
String mensajeDeError(Object error) {
  if (esErrorDeRed(error)) {
    return 'Sin conexión. Revisa tu señal e intenta de nuevo.';
  }
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login credentials')) return 'Usuario o contraseña incorrectos';
    // Mensajes de nuestros hooks (cuenta desactivada, número bloqueado) ya vienen en español.
    return error.message;
  }
  if (error is PostgrestException) {
    if (error.code == '42501' && (error.hint == null || error.hint!.isEmpty)) {
      return 'No tienes permiso para esta acción';
    }
    // Las RPC del proyecto ya responden en español.
    return error.message;
  }
  return 'Ocurrió un error inesperado';
}
