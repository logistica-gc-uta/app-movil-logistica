import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/network/api_exception.dart';
import 'package:app_movil_logistica/features/routes/data/driver_route.dart';

class RoutesException implements Exception {
  const RoutesException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

/// Fecha de hoy en Ecuador (UTC-5, sin horario de verano) con formato
/// YYYY-MM-DD, que es como el backend interpreta el filtro `date`.
String todayInGuayaquil([DateTime? now]) {
  final local = (now ?? DateTime.now()).toUtc().subtract(
    const Duration(hours: 5),
  );
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// Operación en curso, para explicar cada rechazo del servidor.
enum _Operation { read, orderStatus, start, failure, complete, depotReturn }

class RoutesService {
  RoutesService(this.apiClient);

  final ApiClient apiClient;

  /// Rutas del chofer autenticado para [date]. El backend identifica al
  /// chofer por el token, nunca por un id enviado desde la app.
  Future<List<DriverRoute>> fetchMyRoutes(String date) async {
    final data = await _call(
      () => apiClient.get('/drivers/me/routes?date=$date'),
      _Operation.read,
    );
    try {
      return (data as List)
          .cast<Map<String, dynamic>>()
          .map(DriverRoute.fromJson)
          .toList();
    } on TypeError {
      throw const RoutesException(
        'El servidor devolvió rutas inválidas. Actualiza el estado.',
      );
    }
  }

  Future<void> markInTransit(String orderId) =>
      _updateStatus(orderId, 'IN_TRANSIT');

  /// El inicio es idempotente en el servidor. Nunca reenvía automáticamente
  /// la mutación tras un timeout; la pantalla consulta GET para recuperar estado.
  Future<DateTime> startRoute(String routeId) async {
    final data = await _call(
      () => apiClient.post('/routes/${Uri.encodeComponent(routeId)}/start', {}),
      _Operation.start,
    );
    if (data is Map<String, dynamic> &&
        data['id'] == routeId &&
        data['status'] == 'IN_PROGRESS') {
      if (_utc(data['startedAt']) case final time?) return time;
    }
    throw const RoutesException(
      'El servidor no confirmó el inicio de la ruta. Actualiza la lista.',
    );
  }

  Future<void> markDelivered(String orderId) =>
      _updateStatus(orderId, 'DELIVERED');

  /// Registra que la visita no se pudo completar. [requestId] identifica la
  /// solicitud: repetirla con el mismo id y los mismos datos es idempotente.
  /// No cambia el pedido a CANCELLED ni a DELIVERED.
  Future<void> recordFailedVisit({
    required String routeId,
    required String stopId,
    required FailedVisitReason reason,
    required String context,
    required String requestId,
  }) async {
    final data = await _call(
      () => apiClient.post(
        '/routes/${Uri.encodeComponent(routeId)}/stops/'
        '${Uri.encodeComponent(stopId)}/failure',
        {'reason': reason.code, 'context': context, 'requestId': requestId},
      ),
      _Operation.failure,
    );
    if (data is Map<String, dynamic> &&
        data['stopId'] == stopId &&
        data['outcome'] == 'FAILED' &&
        data['failureReason'] == reason.code &&
        data['requestId'] == requestId) {
      return;
    }
    throw const RoutesException(
      'El servidor no confirmó el intento fallido. Actualiza la lista.',
    );
  }

  /// Cierra una ruta con todas sus visitas resueltas. Cerrarla no libera al
  /// chofer: sigue ocupado hasta confirmar su regreso al depósito.
  Future<DateTime> completeRoute(String routeId) async {
    final data = await _call(
      () => apiClient.post(
        '/routes/${Uri.encodeComponent(routeId)}/complete',
        {},
      ),
      _Operation.complete,
    );
    if (data is Map<String, dynamic> &&
        data['id'] == routeId &&
        data['status'] == 'COMPLETED') {
      if (_utc(data['completedAt']) case final time?) return time;
    }
    throw const RoutesException(
      'El servidor no confirmó el cierre de la ruta. Actualiza la lista.',
    );
  }

  /// Confirma la llegada física al depósito de una ruta cerrada o
  /// interrumpida. La disponibilidad devuelta es la que persistió el servidor.
  Future<DepotReturn> confirmReturn(String routeId) async {
    final data = await _call(
      () =>
          apiClient.post('/routes/${Uri.encodeComponent(routeId)}/return', {}),
      _Operation.depotReturn,
    );
    if (data is Map<String, dynamic> &&
        data['id'] == routeId &&
        (data['status'] == 'COMPLETED' || data['status'] == 'INTERRUPTED') &&
        data['availability'] is Map<String, dynamic>) {
      final returnedAt = _utc(data['returnedAt']);
      try {
        final availability = DriverAvailability.fromJson(
          data['availability'] as Map<String, dynamic>,
        );
        if (returnedAt != null) {
          return DepotReturn(
            routeStatus: data['status'] as String,
            returnedAt: returnedAt,
            availability: availability,
          );
        }
      } on TypeError {
        // Respuesta incompleta: se trata igual que una no confirmada.
      }
    }
    throw const RoutesException(
      'El servidor no confirmó tu llegada al depósito. Actualiza la lista.',
    );
  }

  /// Disponibilidad efectiva del chofer autenticado.
  Future<DriverAvailability> fetchMyAvailability() async {
    final data = await _call(
      () => apiClient.get('/drivers/me/availability'),
      _Operation.read,
    );
    try {
      return DriverAvailability.fromJson(data as Map<String, dynamic>);
    } on TypeError {
      throw const RoutesException(
        'El servidor devolvió una disponibilidad inválida.',
      );
    }
  }

  Future<void> _updateStatus(String orderId, String status) async {
    await _call(
      () => apiClient.patch('/orders/$orderId/status', {'status': status}),
      _Operation.orderStatus,
    );
  }

  Future<dynamic> _call(
    Future<dynamic> Function() request,
    _Operation operation,
  ) async {
    try {
      return await request();
    } on ApiException catch (error) {
      throw RoutesException(
        _rejection(error.statusCode, operation),
        statusCode: error.statusCode,
      );
    } on Exception {
      throw const RoutesException('No se pudo conectar con el servidor.');
    }
  }
}

String _rejection(int statusCode, _Operation operation) {
  if (statusCode == 401) return 'Tu sesión caducó. Inicia sesión de nuevo.';
  return switch ((operation, statusCode)) {
    (_Operation.start, 403) => 'No tienes permiso para iniciar esta ruta.',
    (_Operation.start, 409) =>
      'La ruta no se puede iniciar en su estado actual. Actualiza la lista.',
    (_Operation.start, 404) =>
      'La ruta ya no está disponible. Actualiza la lista.',
    (_Operation.failure, 400) =>
      'Revisa el motivo y la descripción del intento fallido.',
    (_Operation.failure, 403) =>
      'No puedes registrar visitas de una ruta que no es tuya.',
    (_Operation.failure, 404) =>
      'La parada ya no está disponible. Actualiza la lista.',
    (_Operation.failure, 409) =>
      'La visita ya no está pendiente o la ruta cambió de estado. '
          'Actualiza la lista.',
    (_Operation.complete, 403) => 'No puedes cerrar una ruta que no es tuya.',
    (_Operation.complete, 404) =>
      'La ruta ya no está disponible. Actualiza la lista.',
    (_Operation.complete, 409) =>
      'El servidor aún no permite cerrar la ruta: revisa que todas las '
          'visitas estén resueltas y actualiza la lista.',
    (_Operation.depotReturn, 403) =>
      'No puedes confirmar el regreso de una ruta que no es tuya.',
    (_Operation.depotReturn, 404) =>
      'La ruta ya no está disponible. Actualiza la lista.',
    (_Operation.depotReturn, 409) =>
      'El servidor aún no habilita el regreso de esta ruta. '
          'Actualiza la lista.',
    (_, 403) =>
      'No puedes hacer esta acción ahora. '
          'Verifica que la ruta esté iniciada.',
    (_, 409) => 'El pedido cambió de estado. Actualiza la lista.',
    _ => 'El servidor respondió con un error.',
  };
}

/// Instantes del servidor: solo se aceptan con zona horaria explícita.
DateTime? _utc(Object? value) {
  if (value is! String) return null;
  final time = DateTime.tryParse(value);
  return time != null && time.isUtc ? time : null;
}
