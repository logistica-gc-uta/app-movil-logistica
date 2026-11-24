import 'package:app_movil_logistica/core/theme/app_theme.dart';
import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_formatters.dart';
import 'package:app_movil_logistica/features/routes/presentation/route_style.dart';
import 'package:flutter/material.dart';

/// Intento fallido enviado y aún sin confirmar.
class FailureDraft {
  const FailureDraft({
    required this.stopId,
    required this.reason,
    required this.context,
    required this.requestId,
  });

  final String stopId;
  final FailedVisitReason reason;
  final String context;
  final String requestId;
}

/// Hoja para registrar por qué no se pudo entregar: motivo tipificado y una
/// descripción obligatoria, como exige el servidor.
class FailedVisitSheet extends StatefulWidget {
  const FailedVisitSheet({
    super.key,
    required this.address,
    this.initialReason,
    this.initialContext,
  });

  final String address;
  final FailedVisitReason? initialReason;
  final String? initialContext;

  @override
  State<FailedVisitSheet> createState() => _FailedVisitSheetState();
}

class _FailedVisitSheetState extends State<FailedVisitSheet> {
  static const maxLength = 500;

  late FailedVisitReason? _reason = widget.initialReason;
  late final _description = TextEditingController(text: widget.initialContext);

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  bool get _isValid => _reason != null && _description.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: RouteTone.track,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'No se pudo entregar',
                textAlign: TextAlign.center,
                style: display(context, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                widget.address,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: RouteTone.muted),
              ),
              const SizedBox(height: 22),
              Text('Motivo', style: overline(context)),
              const SizedBox(height: 4),
              RadioGroup<FailedVisitReason>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  children: [
                    for (final reason in FailedVisitReason.values)
                      RadioListTile<FailedVisitReason>(
                        key: ValueKey('failure-reason-${reason.code}'),
                        value: reason,
                        title: Text(reason.label),
                        activeColor: RouteTone.ink,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('failure-context'),
                controller: _description,
                maxLength: maxLength,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Qué pasó',
                  hintText: 'Ej.: Nadie respondió tras tocar dos veces.',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'El pedido no se cancela: la administración decide si se '
                'reprograma.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: RouteTone.body),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey('submit-failure'),
                onPressed: _isValid
                    ? () => Navigator.of(
                        context,
                      ).pop((_reason!, _description.text.trim()))
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: RouteTone.danger,
                  disabledBackgroundColor: RouteTone.danger.withValues(
                    alpha: 0.35,
                  ),
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text('Registrar intento fallido'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: RouteTone.body,
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmación antes de una acción que no se puede deshacer desde la app.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: RouteRadius.card),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 32, color: RouteTone.ink),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: display(context, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: RouteTone.body),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('confirm-dialog'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: RouteTone.body,
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Finalizar las visitas no implica liberar al conductor ni cerrar su jornada.
class FinishedDialog extends StatelessWidget {
  const FinishedDialog(this.route, {super.key});

  final DriverRoute route;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final perfect = route.failedCount == 0;
    final total = route.stops.length;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: RouteRadius.card),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                perfect
                    ? Icons.check_circle_outline_rounded
                    : Icons.flag_outlined,
                size: 32,
                color: perfect ? RouteTone.success : RouteTone.warning,
              ),
              const SizedBox(height: 18),
              Text(
                perfect ? 'Paradas completadas' : 'Paradas finalizadas',
                textAlign: TextAlign.center,
                style: display(context, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                perfect
                    ? 'Entregaste $total de $total paradas con éxito.'
                    : '${finishedDetail(route)}.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: RouteTone.body),
              ),
              const SizedBox(height: 14),
              Text(
                route.isInProgress
                    ? 'Cierra la ruta y, al llegar al depósito, confirma '
                          'tu llegada.'
                    : route.returnedAt == null
                    ? 'Regresa al depósito y confirma tu llegada.'
                    : 'Regreso al depósito confirmado.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: RouteTone.muted),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Volver a mis rutas'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: RouteTone.body,
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Ver paradas'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de título de la zona privada: la marca y, a la derecha, una acción.
class RouteTopBar extends StatelessWidget implements PreferredSizeWidget {
  const RouteTopBar({
    super.key,
    required this.onBack,
    required this.onLogout,
    required this.onRefresh,
  });

  /// Si no es null, se muestra «Regresar» en lugar de la marca.
  final VoidCallback? onBack;
  final VoidCallback onLogout;

  /// Si no es null, se ofrece actualizar el estado.
  final VoidCallback? onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppBar(
      backgroundColor: RouteTone.page,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 64,
      titleSpacing: AppSpacing.page - 8,
      automaticallyImplyLeading: false,
      title: onBack == null
          ? Text('SPEEDRUN', style: display(context, size: 16))
          : TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              label: const Text('Regresar'),
              style: TextButton.styleFrom(
                foregroundColor: RouteTone.ink,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: weighted(textTheme.bodyLarge, FontWeight.w700),
              ),
            ),
      actions: [
        if (onRefresh != null)
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar estado',
          ),
        if (onBack == null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded, size: 20),
              tooltip: 'Cerrar sesión',
              style: IconButton.styleFrom(
                foregroundColor: RouteTone.ink,
                backgroundColor: RouteTone.surface,
                fixedSize: const Size(44, 44),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.button,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
