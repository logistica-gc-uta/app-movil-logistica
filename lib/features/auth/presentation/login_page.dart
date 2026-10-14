import 'dart:math' as math;

import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/core/widgets/topo_header.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.authService,
    required this.onLoggedIn,
    this.initialMessage,
  });

  final AuthService authService;
  final void Function(AuthSession session) onLoggedIn;
  final String? initialMessage;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _hidePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialMessage;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    String? errorMessage;
    try {
      final session = await widget.authService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      widget.onLoggedIn(session);
    } on AuthException catch (error) {
      errorMessage = error.message;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _errorMessage = errorMessage;
    });
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Escribe tu correo.';
    }
    if (!email.contains('@')) {
      return 'El correo no es válido.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Escribe tu contraseña.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _errorMessage;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final headerHeight = math.max(280.0, constraints.maxHeight * 0.44);

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: headerHeight, child: const _Header()),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                        child: _buildForm(),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 32, 28, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (errorMessage != null) ...[
                              _ErrorBanner(errorMessage),
                              const SizedBox(height: 16),
                            ],
                            _SubmitButton(
                              isLoading: _isLoading,
                              onPressed: _submit,
                            ),
                            const SizedBox(height: 16),
                            const _Footer(),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 24 + MediaQuery.paddingOf(context).bottom,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm() {
    final textTheme = Theme.of(context).textTheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Correo electrónico', style: textTheme.titleMedium),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            style: textTheme.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'tu@correo.com',
              prefixIcon: _FieldIcon(Icons.mail_outline_rounded),
              prefixIconConstraints: BoxConstraints(),
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: 28),
          Text('Contraseña', style: textTheme.titleMedium),
          TextFormField(
            controller: _passwordController,
            obscureText: _hidePassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            style: textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: '••••••••••',
              prefixIcon: const _FieldIcon(Icons.lock_outline_rounded),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _hidePassword = !_hidePassword;
                  });
                },
                icon: Icon(
                  _hidePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                tooltip: _hidePassword
                    ? 'Mostrar contraseña'
                    : 'Ocultar contraseña',
              ),
            ),
            validator: _validatePassword,
          ),
        ],
      ),
    );
  }
}

/// Cabecera coral con el título "Iniciar sesión" sobre la zona blanca.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TopoHeader(
      child: Positioned(
        left: 28,
        bottom: 4,
        child: ConstrainedBox(
          // Deja libre la parte derecha, donde baja la onda coral.
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.55,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Iniciar sesión', style: textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  Container(
                    height: 3,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldIcon extends StatelessWidget {
  const _FieldIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Container(width: 1, height: 14, color: AppColors.line),
        ],
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.onPrimary,
              ),
            )
          : const Text('Ingresar al turno'),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.errorSurface,
        borderRadius: AppRadius.button,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Acceso exclusivo para repartidores',
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
    );
  }
}
