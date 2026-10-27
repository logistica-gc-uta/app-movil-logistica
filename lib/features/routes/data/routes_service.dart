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

class RoutesService {
  RoutesService(this.apiClient);

  final ApiClient apiClient;

  /// Rutas del chofer autenticado para [date]. El backend identifica al
  /// chofer por el token, nunca por un id enviado desde la app.
  Future<List<DriverRoute>> fetchMyRoutes(String date) async {
    final data = await _call(
      () => apiClient.get('/drivers/me/routes?date=$date'),
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
      startingRoute: true,
    );
    if (data is Map<String, dynamic> &&
        data['id'] == routeId &&
        data['status'] == 'IN_PROGRESS' &&
        data['startedAt'] is String) {
      final time = DateTime.tryParse(data['startedAt'] as String);
      if (time != null && time.isUtc) return time;
    }
    throw const RoutesException(
      'El servidor no confirmó el inicio de la ruta. Actualiza la lista.',
    );
  }

  Future<void> markDelivered(String orderId) =>
      _updateStatus(orderId, 'DELIVERED');

  Future<void> _updateStatus(String orderId, String status) async {
    await _call(
      () => apiClient.patch('/orders/$orderId/status', {'status': status}),
    );
  }

  Future<dynamic> _call(
    Future<dynamic> Function() request, {
    bool startingRoute = false,
  }) async {
    try {
      return await request();
    } on ApiException catch (error) {
      throw RoutesException(switch (error.statusCode) {
        401 => 'Tu sesión caducó. Inicia sesión de nuevo.',
        403 when startingRoute => 'No tienes permiso para iniciar esta ruta.',
        403 =>
          'No puedes hacer esta acción ahora. '
              'Verifica que la ruta esté iniciada.',
        409 when startingRoute =>
          'La ruta no se puede iniciar en su estado actual. Actualiza la lista.',
        404 when startingRoute =>
          'La ruta ya no está disponible. Actualiza la lista.',
        409 => 'El pedido cambió de estado. Actualiza la lista.',
        _ => 'El servidor respondió con un error.',
      }, statusCode: error.statusCode);
    } on Exception {
      throw const RoutesException('No se pudo conectar con el servidor.');
    }
  }
}
