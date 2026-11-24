import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../application/auth_controller.dart';

/// Registro de cuenta. Si [invitationToken] no es nulo (deep link
/// agecare://invite/<token>), la cuenta se crea vinculada a esa invitación.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.invitationToken});

  final String? invitationToken;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            // Enlace de invitación o código de 6 dígitos: la cuenta queda
            // vinculada al paciente con el rol de la invitación.
            invitationToken: widget.invitationToken ??
                (_code.text.trim().isEmpty ? null : _code.text.trim()),
          );
      if (!mounted) return;
      final email = _email.text.trim();
      // Vuelve al login (con el correo listo) para que entre con la cuenta nueva.
      if (context.canPop()) {
        context.pop(email);
      } else {
        showAppSnackBar(context, 'Cuenta creada. Ahora inicia sesión.');
        context.go('/login');
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.invitationToken != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.card_giftcard_rounded, color: AppColors.primaryDark),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              'Te invitaron a un círculo de cuidado. Al crear tu cuenta quedarás vinculado.'),
                        ),
                      ],
                    ),
                  ),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Nombre completo', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) =>
                      v != null && v.trim().length >= 2 ? null : 'Escribe tu nombre',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) =>
                      v != null && v.contains('@') ? null : 'Escribe un correo válido',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) {
                    if (v == null || v.length < 8) return 'Mínimo 8 caracteres';
                    final hasLetter = v.contains(RegExp(r'[a-zA-Z]'));
                    final hasNumber = v.contains(RegExp(r'[0-9]'));
                    if (!hasLetter || !hasNumber) {
                      return 'Debe incluir al menos una letra y un número';
                    }
                    return null;
                  },
                ),
                if (widget.invitationToken == null) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('register-code'),
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Código de invitación (opcional)',
                      helperText:
                          'Si te invitaron como cuidadora, adulto mayor o médico, '
                          'escribe el código de 6 dígitos que te dio la familia.',
                      helperMaxLines: 3,
                      prefixIcon: Icon(Icons.pin_outlined),
                      counterText: '',
                    ),
                    validator: (v) {
                      final code = (v ?? '').trim();
                      if (code.isEmpty) return null;
                      return RegExp(r'^\d{6}$').hasMatch(code)
                          ? null
                          : 'El código tiene 6 dígitos';
                    },
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Crear cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
