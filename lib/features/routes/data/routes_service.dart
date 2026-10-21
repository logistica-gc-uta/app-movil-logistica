import 'package:app_movil_logistica/core/network/api_client.dart';
import 'package:app_movil_logistica/core/network/api_exception.dart';
import 'package:app_movil_logistica/features/routes/data/driver_route.dart';

class RoutesException implements Exception {
  const RoutesException(this.message);

  final String message;
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
    return (data as List)
        .cast<Map<String, dynamic>>()
        .map(DriverRoute.fromJson)
        .toList();
  }

  Future<void> markInTransit(String orderId) =>
      _updateStatus(orderId, 'IN_TRANSIT');

  Future<void> markDelivered(String orderId) =>
      _updateStatus(orderId, 'DELIVERED');

  Future<void> _updateStatus(String orderId, String status) async {
    await _call(
      () => apiClient.patch('/orders/$orderId/status', {'status': status}),
    );
  }

  Future<dynamic> _call(Future<dynamic> Function() request) async {
    try {
      return await request();
    } on ApiException catch (error) {
      throw RoutesException(switch (error.statusCode) {
        401 => 'Tu sesión caducó. Inicia sesión de nuevo.',
        403 =>
          'No puedes hacer esta acción ahora. '
              'Verifica que la ruta esté iniciada.',
        409 => 'El pedido cambió de estado. Actualiza la lista.',
        _ => 'El servidor respondió con un error.',
      });
    } on Exception {
      throw const RoutesException('No se pudo conectar con el servidor.');
    }
  }
}
