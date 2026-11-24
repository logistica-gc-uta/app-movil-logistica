import 'package:app_movil_logistica/features/routes/data/driver_route.dart';

/// Hora confirmada por el servidor, independiente de la zona del teléfono.
String formatRouteStart(DateTime time) =>
    'Inicio: ${formatEcuadorTime(time)} (Ecuador)';

/// `HH:mm` en hora de Ecuador (UTC-5), sin depender de la zona del teléfono.
String formatEcuadorTime(DateTime time) {
  final local = time.toUtc().subtract(const Duration(hours: 5));
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

const _weekdays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Convierte `2026-10-18` en «Domingo 18 de octubre».
String formatLongDate(String isoDate) {
  final parts = isoDate.split('-').map(int.parse).toList();
  final day = DateTime.utc(parts[0], parts[1], parts[2]);
  final weekday = _weekdays[day.weekday - 1];
  final capitalized = weekday[0].toUpperCase() + weekday.substring(1);
  return '$capitalized ${day.day} de ${_months[day.month - 1]}';
}

/// «1 parada» o «N paradas».
String stopsCount(int total) => total == 1 ? '1 parada' : '$total paradas';

/// Cuenta solo entregas reales: un intento fallido no suma como entregado.
String progressText(DriverRoute route) {
  final total = route.stops.length;
  final failed = route.failedCount;
  final delivered = '${route.deliveredCount} de $total entregados';
  return failed == 0 ? delivered : '$delivered · $failed con intento fallido';
}

String resolvedText(DriverRoute route) =>
    '${(route.deliveredFraction * 100).round()} % entregado · '
    '${route.resolvedCount}/${route.stops.length} visitas resueltas';

/// Resultado de una ruta con todas sus paradas resueltas, sin dar por
/// exitosa una visita fallida.
String finishedDetail(DriverRoute route) {
  final delivered = route.deliveredCount;
  final failed = route.failedCount;
  final ok = delivered == 1
      ? '1 entrega exitosa'
      : '$delivered entregas exitosas';
  return failed == 0 ? ok : '$ok · $failed con intento fallido';
}

/// Estado comercial separado del resultado persistido de la visita.
String stopStatusLabel(DeliveryStop stop) {
  if (stop.hasPersistedVisit && stop.status == 'DELIVERED') {
    return 'Visita sin confirmar';
  }
  return switch (stop.status) {
    'IN_TRANSIT' => 'En camino',
    'CANCELLED' => 'Cancelado',
    'PENDING' => 'Pendiente',
    _ => 'Por entregar',
  };
}

/// «Intento fallido», con su motivo cuando el servidor lo informa.
String failedLabel(DeliveryStop stop) => switch (stop.failureReason) {
  final reason? => 'Intento fallido · ${reason.label}',
  null => 'Intento fallido',
};

/// Aviso de cada estado de ruta.
String? routeHint(DriverRoute route) {
  return switch (route.status) {
    'IN_PROGRESS' when route.allStopsResolved =>
      'Todas las visitas están resueltas. Cierra la ruta para registrar su fin.',
    'INTERRUPTED' when route.returnedAt == null =>
      'La administración interrumpió esta ruta. No atiendas más paradas: '
          'regresa al depósito y confirma tu llegada.',
    'INTERRUPTED' =>
      'Ruta interrumpida. Regreso al depósito confirmado; la administración '
          'gestiona los pedidos pendientes.',
    'COMPLETED' when route.returnedAt == null =>
      'Visitas finalizadas. Sigues ocupado: regresa al depósito y confirma tu llegada.',
    'COMPLETED' => 'Visitas finalizadas. Regreso al depósito confirmado.',
    _ => null,
  };
}
