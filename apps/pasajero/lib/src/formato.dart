const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "mié 1 oct, 8:35 p. m." en la hora del teléfono.
String fechaCorta(DateTime fecha) {
  final f = fecha.toLocal();
  final hora12 = f.hour % 12 == 0 ? 12 : f.hour % 12;
  final ampm = f.hour < 12 ? 'a. m.' : 'p. m.';
  return '${_dias[f.weekday - 1]} ${f.day} ${_meses[f.month - 1]}, '
      '$hora12:${f.minute.toString().padLeft(2, '0')} $ampm';
}

/// "+529511234567" → "951 123 4567"
String telefonoLegible(String? telefono) {
  final m = RegExp(r'^\+52(\d{3})(\d{3})(\d{4})$').firstMatch(telefono ?? '');
  return m == null ? (telefono ?? '') : '${m[1]} ${m[2]} ${m[3]}';
}

/// Cómo terminó (o en qué va) un viaje, para el historial.
String textoEstado(String estado) => switch (estado) {
      'completado' => 'Completado',
      'cancelado' => 'Cancelado',
      'sin_conductor' => 'Sin taxi disponible',
      'buscando' => 'Buscando taxi',
      'asignado' => 'Taxi en camino',
      'conductor_llego' => 'El taxi llegó',
      'en_curso' => 'En viaje',
      _ => estado,
    };
