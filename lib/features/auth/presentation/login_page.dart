import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/core/widgets/brand_wordmark.dart';
import 'package:app_movil_logistica/core/widgets/primary_button.dart';
import 'package:app_movil_logistica/features/auth/data/auth_service.dart';
import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:app_movil_logistica/features/auth/presentation/welcome_page.dart';
import 'package:flutter/material.dart';

/// Distancia desde arriba a la que queda "SPEED RUN" en el inicio de sesión.
double loginWordmarkTop(BuildContext context) {
  return MediaQuery.paddingOf(context).top + 96;
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.authService,
    required this.onLoggedIn,
    this.initialMessage,
    this.revealFromWelcome = false,
  });

  final AuthService authService;
  final void Function(AuthSession session) onLoggedIn;
  final String? initialMessage;

  /// Si es true, la pantalla arranca con el aspecto de la bienvenida y el
  /// fondo sube hasta cubrir el bloque de marca mientras suben los campos.
  final bool revealFromWelcome;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _intro;

  /// Avance del fondo que sube: de su borde en la bienvenida hasta arriba
  /// del todo. Sin bienvenida previa ya lo cubre todo.
  late final Animation<double> _sheet;

  /// Avance de los campos: suben deslizándose mientras se aclaran.
  late final Animation<double> _form;

  /// Salida del texto de la bienvenida: se desvanece al empezar a subir el
  /// fondo, antes de alcanzar la marca.
  late final Animation<double> _copyOut;

  /// Se vuelve true cuando termina la animación de entrada.
  bool _introDone = false;

  bool _isLoading = false;
  bool _hidePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialMessage;
    final fromWelcome = widget.revealFromWelcome;
    _intro = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: fromWelcome ? 900 : 450),
    );
    _sheet = fromWelcome
        ? CurvedAnimation(
            parent: _intro,
            curve: const Interval(0, 0.75, curve: Curves.easeInOutCubic),
          )
        : const AlwaysStoppedAnimation(1);
    // Con bienvenida previa, los campos empiezan a subir cuando el fondo ya
    // va subiendo, y terminan un poco después que él.
    _form = CurvedAnimation(
      parent: _intro,
      curve: fromWelcome
          ? const Interval(0.25, 1, curve: Curves.easeOutCubic)
          : Curves.easeOutCubic,
    );
    _copyOut = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.22, curve: Curves.easeOut),
    );
    _intro
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _introDone = true;
          });
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
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
    final brand = BrandColors.of(context);
    final screen = MediaQuery.sizeOf(context);
    final intro = widget.revealFromWelcome && !_introDone;
    // El borde superior del fondo parte del final del bloque de marca de la
    // bienvenida y sube hasta arriba.
    final edgeStart = widget.revealFromWelcome
        ? welcomeBlockHeight(screen)
        : 0.0;
    // Cuánto más abajo estaba la marca en la bienvenida.
    final wordmarkShift = widget.revealFromWelcome
        ? welcomeWordmarkTop(context) - loginWordmarkTop(context)
        : 0.0;
    // Desde dónde suben los campos.
    final formShift = widget.revealFromWelcome ? 160.0 : 40.0;
    final wordmarkTop = loginWordmarkTop(context);

    return AnnotatedRegion(
      value: statusBarFor(brand.base),
      child: Scaffold(
        backgroundColor: brand.base,
        // Cada animación mueve solo su pieza; el resto de la pantalla no se
        // reconstruye en cada fotograma.
        body: Stack(
          children: [
            if (intro) ...[
              // Bloque de marca que el fondo va cubriendo al subir.
              AnimatedBuilder(
                animation: _sheet,
                builder: (context, child) => Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: edgeStart * (1 - _sheet.value),
                  child: child!,
                ),
                child: ColoredBox(color: brand.block),
              ),
              // El texto de la bienvenida sube con el fondo y se desvanece
              // enseguida.
              AnimatedBuilder(
                animation: _sheet,
                builder: (context, child) => Positioned(
                  left: AppSpacing.page,
                  right: AppSpacing.page,
                  top: welcomeCopyTop(screen) - edgeStart * _sheet.value,
                  child: child!,
                ),
                child: FadeTransition(
                  opacity: ReverseAnimation(_copyOut),
                  child: const WelcomeCopy(),
                ),
              ),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // Solo se ve lo que ya está sobre el fondo: los campos y la
                  // marca en su color aparecen a medida que sube.
                  child: ClipRect(
                    clipper: _EdgeClipper(
                      progress: _sheet,
                      edgeStart: edgeStart,
                      keepBelow: true,
                    ),
                    child: _buildContent(
                      wordmarkShift: wordmarkShift,
                      formShift: formShift,
                    ),
                  ),
                ),
                // El botón queda en la misma posición que en la bienvenida.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    12,
                    AppSpacing.page,
                    12 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: PrimaryButton(
                    label: 'Ingresar al turno',
                    isLoading: _isLoading,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
            if (intro)
              // La parte de la marca que aún está sobre el bloque se ve en el
              // color del bloque: al pasar el borde, las letras cambian de
              // color justo en esa línea.
              Positioned.fill(
                child: ClipRect(
                  clipper: _EdgeClipper(
                    progress: _sheet,
                    edgeStart: edgeStart,
                    keepBelow: false,
                  ),
                  child: Stack(
                    children: [
                      AnimatedBuilder(
                        animation: _sheet,
                        builder: (context, child) => Positioned(
                          left: AppSpacing.page,
                          right: AppSpacing.page,
                          top: wordmarkTop + wordmarkShift * (1 - _sheet.value),
                          child: child!,
                        ),
                        child: BrandWordmark(
                          color: brand.onBlock,
                          showLines: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({
    required double wordmarkShift,
    required double formShift,
  }) {
    final errorMessage = _errorMessage;
    final onBase = BrandColors.of(context).onBase;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.page,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: loginWordmarkTop(context)),
                    // La marca sube desde su sitio en la bienvenida.
                    AnimatedBuilder(
                      animation: _sheet,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, wordmarkShift * (1 - _sheet.value)),
                        child: child,
                      ),
                      child: BrandWordmark(color: onBase, showLines: true),
                    ),
                    // El formulario queda centrado entre la marca y el botón:
                    // mismo espacio arriba y abajo, con un mínimo para
                    // pantallas bajas. Los 6 extra compensan el margen propio
                    // del botón.
                    const SizedBox(height: AppSpacing.page + 6),
                    const Spacer(),
                    // Los campos suben deslizándose mientras se aclaran.
                    AnimatedBuilder(
                      animation: _form,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, formShift * (1 - _form.value)),
                        child: child,
                      ),
                      child: FadeTransition(
                        opacity: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildForm(),
                            if (errorMessage != null) ...[
                              const SizedBox(height: 20),
                              _ErrorBanner(errorMessage),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: AppSpacing.page),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildForm() {
    final textTheme = Theme.of(context).textTheme;
    final onBase = BrandColors.of(context).onBase;
    final fieldText = textTheme.bodyLarge?.copyWith(color: AppColors.ink);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Línea fina que separa la marca del formulario.
          Container(height: 1, color: onBase.withValues(alpha: 0.4)),
          const SizedBox(height: 20),
          Text(
            'INICIAR SESIÓN',
            style: textTheme.titleLarge?.copyWith(
              color: onBase,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontVariations: const [FontVariation.weight(800)],
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 20),
          const _FieldLabel('Correo'),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            style: fieldText,
            decoration: _fieldDecoration('tu@correo.com'),
            validator: _validateEmail,
          ),
          const SizedBox(height: 22),
          const _FieldLabel('Contraseña'),
          TextFormField(
            controller: _passwordController,
            obscureText: _hidePassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            style: fieldText,
            decoration: _fieldDecoration('••••••••••').copyWith(
              // El ojo va en un segmento blanco aparte, separado por una línea.
              suffixIconConstraints: const BoxConstraints.tightFor(
                width: 47,
                height: 40,
              ),
              suffixIcon: Container(
                margin: const EdgeInsets.only(right: 1),
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  border: Border(
                    left: BorderSide(color: AppColors.fieldBorder),
                  ),
                ),
                child: IconButton(
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
            ),
            validator: _validatePassword,
          ),
        ],
      ),
    );
  }

  /// Campos más bajos que los del tema y con el mensaje de error en el color
  /// de los textos del fondo, para que se lea sobre él.
  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      errorStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: BrandColors.of(context).onBase,
        fontWeight: FontWeight.w600,
        fontVariations: const [FontVariation.weight(600)],
      ),
    );
  }
}

/// Recorta según el borde del fondo que sube, sin reconstruir lo recortado.
/// Con [keepBelow] deja ver lo que está debajo del borde (sobre el fondo); si
/// no, lo que está encima (sobre el bloque de marca).
class _EdgeClipper extends CustomClipper<Rect> {
  _EdgeClipper({
    required this.progress,
    required this.edgeStart,
    required this.keepBelow,
  }) : super(reclip: progress);

  final Animation<double> progress;
  final double edgeStart;
  final bool keepBelow;

  @override
  Rect getClip(Size size) {
    final edge = edgeStart * (1 - progress.value);
    return keepBelow
        ? Rect.fromLTRB(0, edge, size.width, size.height)
        : Rect.fromLTRB(0, 0, size.width, edge);
  }

  @override
  bool shouldReclip(_EdgeClipper oldClipper) {
    return oldClipper.progress != progress ||
        oldClipper.edgeStart != edgeStart ||
        oldClipper.keepBelow != keepBelow;
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: BrandColors.of(context).onBase,
          fontWeight: FontWeight.w700,
          fontVariations: const [FontVariation.weight(700)],
        ),
      ),
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
