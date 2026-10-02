import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';

import '../formato.dart';

final miPerfilProvider = FutureProvider<({String nombre, String telefono})>((ref) async {
  final supabase = ref.watch(supabaseProvider);
  final fila = await supabase
      .from('perfiles')
      .select('nombre, telefono')
      .eq('id', supabase.auth.currentUser!.id)
      .single();
  return (nombre: fila['nombre'] as String, telefono: fila['telefono'] as String);
});

/// Ver y cambiar nombre o teléfono. Al final, cerrar sesión (con advertencia:
/// el pasajero no tiene contraseña, así que la cuenta no se puede recuperar).
class PantallaPerfil extends ConsumerWidget {
  const PantallaPerfil({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis datos')),
      body: Column(
        children: [
          const BannerConexion(),
          Expanded(
            child: ref.watch(miPerfilProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: MensajeError(mensajeDeError(e))),
                  data: (perfil) => _Formulario(nombre: perfil.nombre, telefono: perfil.telefono),
                ),
          ),
        ],
      ),
    );
  }
}

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({required this.nombre, required this.telefono});

  final String nombre;
  final String telefono;

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  final _formulario = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.nombre);
  late final _telefono = TextEditingController(text: telefonoLegible(widget.telefono));
  bool _guardando = false;
  String? _error;
  String? _listo;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
      _listo = null;
    });
    try {
      await ref.read(supabaseProvider).rpc('registrar_pasajero', params: {
        'p_nombre': _nombre.text.trim(),
        'p_telefono': _telefono.text,
      });
      ref.invalidate(miPerfilProvider);
      if (mounted) setState(() => _listo = 'Datos guardados ✓');
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Tu cuenta no tiene contraseña: si cierras sesión, en este teléfono ya no '
          'podrás ver tu historial de viajes. Tendrás que registrarte de nuevo.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No, quedarme')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, cerrar sesión', style: TextStyle(color: ColoresTaxi.rojo)),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(supabaseProvider).auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formulario,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: _nombre,
            decoration: const InputDecoration(labelText: 'Tu nombre'),
            style: const TextStyle(fontSize: 20),
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v == null || v.trim().length < 2) ? 'Escribe tu nombre' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _telefono,
            decoration: const InputDecoration(labelText: 'Tu teléfono'),
            style: const TextStyle(fontSize: 20),
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]'))],
            validator: (v) {
              final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
              return d.length == 10 || (d.length == 12 && d.startsWith('52')) ? null : 'Escribe tu teléfono a 10 dígitos';
            },
          ),
          const SizedBox(height: 16),
          MensajeError(_error),
          if (_listo != null)
            Text(_listo!, style: const TextStyle(fontSize: 18, color: ColoresTaxi.verde)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _guardando ? null : _guardar, child: Text(_guardando ? 'Guardando…' : 'Guardar')),
          const SizedBox(height: 48),
          TextButton(
            onPressed: _cerrarSesion,
            child: const Text('Cerrar sesión', style: TextStyle(fontSize: 18, color: ColoresTaxi.rojo)),
          ),
        ],
      ),
    );
  }
}
