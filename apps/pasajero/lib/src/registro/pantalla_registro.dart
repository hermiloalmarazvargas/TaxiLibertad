import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';

/// Registro del pasajero: solo nombre y teléfono, sin contraseña ni SMS.
///
/// Por dentro: sesión anónima de Supabase + registrar_pasajero. La sesión se
/// queda guardada en el teléfono. (Más adelante se podrá verificar el
/// teléfono por SMS sobre esta misma cuenta, sin perder el historial.)
class PantallaRegistro extends ConsumerStatefulWidget {
  const PantallaRegistro({super.key});

  @override
  ConsumerState<PantallaRegistro> createState() => _PantallaRegistroState();
}

class _PantallaRegistroState extends ConsumerState<PantallaRegistro> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    final auth = ref.read(supabaseProvider).auth;
    try {
      // Si ya había una sesión anónima (p. ej. se cayó la señal a medio
      // registro), se reutiliza en vez de crear otra cuenta.
      if (auth.currentSession == null) await auth.signInAnonymously();
      await ref.read(supabaseProvider).rpc('registrar_pasajero', params: {
        'p_nombre': _nombre.text.trim(),
        'p_telefono': _telefono.text,
      });
      // El token nuevo trae rol=pasajero; el router lleva a la pantalla principal.
      await auth.refreshSession();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const BannerConexion(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formulario,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.local_taxi, size: 72, color: ColoresTaxi.ambar),
                        Text('Taxi Miahuatlán', style: texto.headlineMedium, textAlign: TextAlign.center),
                        Text('Pide tu taxi de sitio', style: texto.bodyLarge, textAlign: TextAlign.center),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _nombre,
                          decoration: const InputDecoration(labelText: 'Tu nombre'),
                          style: const TextStyle(fontSize: 20),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          validator: (v) => (v == null || v.trim().length < 2) ? 'Escribe tu nombre' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _telefono,
                          decoration: const InputDecoration(
                            labelText: 'Tu teléfono',
                            helperText: '10 dígitos. El taxista y el sitio lo usan para llamarte.',
                            helperMaxLines: 2,
                          ),
                          style: const TextStyle(fontSize: 20),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]'))],
                          autofillHints: const [AutofillHints.telephoneNumber],
                          onFieldSubmitted: (_) => _registrar(),
                          validator: (v) {
                            final digitos = (v ?? '').replaceAll(RegExp(r'\D'), '');
                            final ok = digitos.length == 10 || (digitos.length == 12 && digitos.startsWith('52'));
                            return ok ? null : 'Escribe tu teléfono a 10 dígitos';
                          },
                        ),
                        const SizedBox(height: 16),
                        MensajeError(_error),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _enviando ? null : _registrar,
                          child: Text(_enviando ? 'Un momento…' : 'Empezar'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Solo guardamos tu nombre, tu teléfono y tus viajes.',
                          style: texto.bodyMedium?.copyWith(color: ColoresTaxi.gris),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
