import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_core/taxi_core.dart';

/// Lo que el conductor ve de sí mismo al abrir la app.
class DatosConductor {
  const DatosConductor({
    required this.id,
    required this.nombre,
    required this.sitio,
    required this.estado,
    this.motivoFuera,
    this.unidadId,
    this.unidad,
  });

  final String id;
  final String nombre;
  final String sitio;

  /// 'fuera_de_servicio' | 'disponible' | 'ocupado'
  final String estado;

  /// 'manual' | 'sin_respuesta' | 'desactivado' (solo fuera de servicio)
  final String? motivoFuera;

  final int? unidadId;

  /// Número económico de la unidad en servicio.
  final String? unidad;

  bool get enServicio => estado != 'fuera_de_servicio';
}

final datosConductorProvider = FutureProvider<DatosConductor>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final id = supabase.auth.currentUser!.id;
  final fila = await supabase
      .from('conductores')
      .select('perfil:perfiles(nombre), sitio:sitios(nombre), '
          'estado:conductor_estado(estado, motivo_fuera, unidad_id, unidad:unidades(numero_economico))')
      .eq('perfil_id', id)
      .single();

  final estado = fila['estado'] as Map<String, dynamic>?;
  return DatosConductor(
    id: id,
    nombre: (fila['perfil'] as Map<String, dynamic>)['nombre'] as String,
    sitio: (fila['sitio'] as Map<String, dynamic>)['nombre'] as String,
    estado: estado?['estado'] as String? ?? 'fuera_de_servicio',
    motivoFuera: estado?['motivo_fuera'] as String?,
    unidadId: estado?['unidad_id'] as int?,
    unidad: (estado?['unidad'] as Map<String, dynamic>?)?['numero_economico'] as String?,
  );
});

class Unidad {
  const Unidad({required this.id, required this.numero, required this.placas, this.descripcion});

  final int id;
  final String numero;
  final String placas;
  final String? descripcion;
}

/// Unidades activas del sitio del conductor (RLS ya filtra por su sitio).
final unidadesProvider = FutureProvider<List<Unidad>>((ref) async {
  final filas = await ref
      .watch(supabaseProvider)
      .from('unidades')
      .select('id, numero_economico, placas, marca, color')
      .eq('activo', true)
      .order('numero_economico');
  return [
    for (final f in filas)
      Unidad(
        id: f['id'] as int,
        numero: f['numero_economico'] as String,
        placas: f['placas'] as String,
        descripcion: [f['marca'], f['color']].whereType<String>().join(' · '),
      ),
  ];
});

const _kUltimaUnidad = 'ultima_unidad';

/// La última unidad que manejó el conductor, para tenerla ya elegida.
Future<int?> ultimaUnidad() => SharedPreferencesAsync().getInt(_kUltimaUnidad);
Future<void> recordarUnidad(int id) => SharedPreferencesAsync().setInt(_kUltimaUnidad, id);
