import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/core/theme/palette_storage.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/auth/data/onboarding_storage.dart';
import 'package:app_movil_logistica/features/auth/presentation/login_page.dart';
import 'package:app_movil_logistica/features/auth/presentation/welcome_page.dart';
import 'package:app_movil_logistica/features/routes/presentation/my_route_page.dart';
import 'package:flutter/material.dart';

class LogisticaApp extends StatefulWidget {
  LogisticaApp({
    super.key,
    required this.authService,
    OnboardingStorage? onboardingStorage,
    PaletteStorage? paletteStorage,
  }) : onboardingStorage = onboardingStorage ?? OnboardingStorage(),
       paletteStorage = paletteStorage ?? PaletteStorage();

  final AuthService authService;
  final OnboardingStorage onboardingStorage;
  final PaletteStorage paletteStorage;

  @override
  State<LogisticaApp> createState() => _LogisticaAppState();
}

class _LogisticaAppState extends State<LogisticaApp> {
  bool _isRestoring = true;
  AppPalette _palette = AppPalette.coral;
  bool _showWelcome = false;
  AuthSession? _session;
  String? _loginMessage;

  @override
  void initState() {
    super.initState();
    widget.authService.apiClient.onUnauthorized = _expireSession;
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final session = await widget.authService.restoreSession();
    final seenWelcome = await widget.onboardingStorage.hasSeenWelcome();
    final palette = await widget.paletteStorage.read();
    setState(() {
      _session = session;
      _palette = palette;
      _showWelcome = !seenWelcome;
      _isRestoring = false;
    });
  }

  Future<void> _changePalette(AppPalette palette) async {
    setState(() {
      _palette = palette;
    });
    await widget.paletteStorage.save(palette);
  }

  Future<void> _finishWelcome() async {
    await widget.onboardingStorage.markWelcomeSeen();
    setState(() {
      _showWelcome = false;
    });
  }

  Future<void> _logout() async {
    await widget.authService.logout();
    setState(() {
      _session = null;
    });
  }

  Future<void> _expireSession() async {
    await widget.authService.logout();
    setState(() {
      _session = null;
      _loginMessage = 'Tu sesión caducó. Inicia sesión de nuevo.';
    });
  }

  Widget _buildHome() {
    final session = _session;
    if (_isRestoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session == null && _showWelcome) {
      return WelcomePage(onContinue: _finishWelcome);
    }
    if (session == null) {
      return LoginPage(
        authService: widget.authService,
        initialMessage: _loginMessage,
        onLoggedIn: (newSession) {
          setState(() {
            _session = newSession;
            _loginMessage = null;
          });
        },
      );
    }
    return MyRoutePage(user: session.user, onLogout: _logout);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speedrun',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(primary: _palette.color),
      home: _buildHome(),
      builder: (context, child) {
        // El selector de colores flota sobre todas las pantallas.
        return Stack(
          children: [
            child!,
            _PaletteSwitcher(palette: _palette, onChanged: _changePalette),
          ],
        );
      },
    );
  }
}

/// Botón para elegir la paleta de colores de la app. Cada toque pasa a la
/// siguiente, y la elección se guarda en el teléfono.
class _PaletteSwitcher extends StatelessWidget {
  const _PaletteSwitcher({required this.palette, required this.onChanged});

  final AppPalette palette;
  final ValueChanged<AppPalette> onChanged;

  @override
  Widget build(BuildContext context) {
    final next =
        AppPalette.values[(palette.index + 1) % AppPalette.values.length];

    return SafeArea(
      child: Align(
        // Arriba al centro: no tapa la marca ni el botón de cerrar sesión.
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: Colors.white,
            elevation: 3,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onChanged(next),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: palette.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      palette.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
