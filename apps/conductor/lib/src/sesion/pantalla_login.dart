import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:taxi_core/taxi_core.dart';

class PantallaLogin extends ConsumerStatefulWidget {
  const PantallaLogin({super.key});

  @override
  ConsumerState<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends ConsumerState<PantallaLogin> {
  final _formulario = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _password = TextEditingController();
  bool _verPassword = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });

    final auth = ref.read(supabaseProvider).auth;
    try {
      final respuesta = await auth.signInWithPassword(
        email: correoDeUsuario(_usuario.text),
        password: _password.text,
      );
      final rol = leerClaims(respuesta.session!.accessToken).rol;
      if (rol != 'conductor') {
        await auth.signOut();
        _mostrarError('Esta cuenta no es de conductor. Usa el panel de despacho.');
      }
      // Si todo salió bien, el router lleva a la pantalla de inicio.
    } catch (e) {
      _mostrarError(mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _mostrarError(String mensaje) {
    if (mounted) setState(() => _error = mensaje);
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
                        const SizedBox(height: 8),
                        Text('Taxi Miahuatlán', style: texto.headlineMedium, textAlign: TextAlign.center),
                        Text('App del conductor', style: texto.bodyLarge, textAlign: TextAlign.center),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _usuario,
                          decoration: const InputDecoration(labelText: 'Usuario'),
                          style: const TextStyle(fontSize: 20),
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.none,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe tu usuario' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            suffixIcon: IconButton(
                              iconSize: 28,
                              tooltip: _verPassword ? 'Ocultar contraseña' : 'Ver contraseña',
                              icon: Icon(_verPassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _verPassword = !_verPassword),
                            ),
                          ),
                          style: const TextStyle(fontSize: 20),
                          obscureText: !_verPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _entrar(),
                          validator: (v) => (v == null || v.isEmpty) ? 'Escribe tu contraseña' : null,
                        ),
                        const SizedBox(height: 16),
                        MensajeError(_error),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _enviando ? null : _entrar,
                          child: Text(_enviando ? 'Entrando…' : 'Entrar'),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '¿No tienes usuario o lo olvidaste? Pídelo al administrador de tu sitio.',
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
