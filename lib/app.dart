import 'package:app_movil_logistica/core/config/app_config.dart';
import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/core/theme/brand_storage.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/auth/data/onboarding_storage.dart';
import 'package:app_movil_logistica/features/auth/presentation/login_page.dart';
import 'package:app_movil_logistica/features/auth/presentation/welcome_page.dart';
import 'package:app_movil_logistica/features/routes/data/routes_service.dart';
import 'package:app_movil_logistica/features/routes/presentation/my_route_page.dart';
import 'package:flutter/material.dart';

enum _Screen { welcome, login, route }

/// Efecto de "pasar página": la pantalla nueva entra desde la derecha y la
/// anterior se aparta un poco hacia la izquierda mientras se desvanece.
Widget _pageTransition(
  Widget child,
  Animation<double> animation, {
  required bool isIncoming,
  required bool instant,
}) {
  if (instant) {
    return child;
  }
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  final offset = Tween<Offset>(
    begin: isIncoming ? const Offset(1, 0) : const Offset(-0.3, 0),
    end: Offset.zero,
  ).animate(curved);

  return SlideTransition(
    position: offset,
    child: isIncoming ? child : FadeTransition(opacity: curved, child: child),
  );
}

class LogisticaApp extends StatefulWidget {
  LogisticaApp({
    super.key,
    required this.authService,
    OnboardingStorage? onboardingStorage,
    BrandStorage? brandStorage,
  }) : onboardingStorage = onboardingStorage ?? OnboardingStorage(),
       brandStorage = brandStorage ?? BrandStorage();

  final AuthService authService;
  final OnboardingStorage onboardingStorage;
  final BrandStorage brandStorage;

  @override
  State<LogisticaApp> createState() => _LogisticaAppState();
}

class _LogisticaAppState extends State<LogisticaApp> {
  late final _routesService = RoutesService(widget.authService.apiClient);
  bool _isRestoring = true;

  /// Pantalla mostrada en el último cambio y si ese cambio es inmediato.
  _Screen? _shownScreen;
  bool _instant = false;
  bool _invertBrand = false;
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
    final inverted = await widget.brandStorage.readInverted();
    setState(() {
      _session = session;
      _invertBrand = inverted;
      _showWelcome = AppConfig.alwaysShowWelcome || !seenWelcome;
      _isRestoring = false;
    });
  }

  Future<void> _toggleInvert() async {
    final inverted = !_invertBrand;
    setState(() {
      _invertBrand = inverted;
    });
    await widget.brandStorage.saveInverted(inverted);
  }

  Future<void> _finishWelcome() async {
    // Primero se cambia de pantalla, para que la animación empiece al
    // instante; guardar en el teléfono puede tardar un momento.
    setState(() {
      _showWelcome = false;
    });
    await widget.onboardingStorage.markWelcomeSeen();
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
    if (_isRestoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final screen = _currentScreen();
    if (screen != _shownScreen) {
      // De la bienvenida al login el cambio es inmediato: el login arranca
      // con el mismo aspecto y él mismo estira el bloque de color. En los
      // demás cambios la nueva pantalla entra deslizándose.
      _instant = _shownScreen == _Screen.welcome && screen == _Screen.login;
      _shownScreen = screen;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      transitionBuilder: (child, animation) => _pageTransition(
        child,
        animation,
        isIncoming: child.key == ValueKey(screen),
        instant: _instant,
      ),
      child: KeyedSubtree(key: ValueKey(screen), child: _buildScreen(screen)),
    );
  }

  _Screen _currentScreen() {
    if (_showWelcome) {
      return _Screen.welcome;
    }
    return _session != null ? _Screen.route : _Screen.login;
  }

  Widget _buildScreen(_Screen screen) {
    final session = _session;
    if (screen == _Screen.welcome) {
      return WelcomePage(onContinue: _finishWelcome);
    }
    if (session == null) {
      return LoginPage(
        authService: widget.authService,
        initialMessage: _loginMessage,
        // Viniendo de la bienvenida, el login continúa su animación.
        revealFromWelcome: _instant,
        onLoggedIn: (newSession) {
          setState(() {
            _session = newSession;
            _loginMessage = null;
          });
        },
      );
    }
    return MyRoutePage(
      user: session.user,
      routesService: _routesService,
      onLogout: _logout,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speedrun',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(invertBrand: _invertBrand),
      home: _buildHome(),
      builder: (context, child) {
        // En la bienvenida y el inicio de sesión, el botón para invertir
        // los colores flota en la esquina superior derecha.
        if (_isRestoring || _currentScreen() == _Screen.route) {
          return child!;
        }
        return Stack(
          children: [
            child!,
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, right: 12),
                  child: _InvertSwitch(
                    inverted: _invertBrand,
                    onPressed: _toggleInvert,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Botón para invertir los colores de la bienvenida y del inicio de sesión:
/// intercambia el blanco y el negro.
class _InvertSwitch extends StatelessWidget {
  const _InvertSwitch({required this.inverted, required this.onPressed});

  final bool inverted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      child: InkWell(
        customBorder: const RoundedRectangleBorder(
          borderRadius: AppRadius.button,
        ),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.invert_colors, size: 14, color: AppColors.ink),
              const SizedBox(width: 6),
              Text(
                inverted ? 'Normal' : 'Invertir',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
