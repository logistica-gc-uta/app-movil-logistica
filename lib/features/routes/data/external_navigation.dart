import 'package:app_movil_logistica/features/routes/data/driver_route.dart';
import 'package:url_launcher/url_launcher.dart';

/// Aplicaciones de navegación externa soportadas para guiar al chofer.
enum ExternalMapApp {
  googleMaps('Google Maps'),
  waze('Waze');

  const ExternalMapApp(this.label);

  final String label;
}

/// Función inyectable para abrir enlaces externos (permite pruebas sin plataforma).
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultUrlLauncher(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Construye y abre enlaces de navegación externa en Google Maps y Waze.
class ExternalNavigator {
  const ExternalNavigator({ExternalUrlLauncher? launcher})
    : _launcher = launcher ?? _defaultUrlLauncher;

  /// Límite práctico de Google Maps móvil por URL: 9 waypoints + 1 destino.
  static const int maxGoogleMapsStops = 10;

  final ExternalUrlLauncher _launcher;

  /// Enlace para navegar hacia una parada individual.
  static Uri buildStopUri(DeliveryStop stop, ExternalMapApp app) {
    if (stop.hasCoordinates) {
      return buildCoordinatesUri(
        lat: stop.deliveryLat!,
        lng: stop.deliveryLng!,
        app: app,
      );
    }
    return switch (app) {
      ExternalMapApp.googleMaps => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': stop.address,
        'travelmode': 'driving',
      }),
      ExternalMapApp.waze => Uri.https('waze.com', '/ul', {
        'q': stop.address,
        'navigate': 'yes',
      }),
    };
  }

  /// Enlace para navegar hacia unas coordenadas exactas (por ejemplo, el depósito).
  static Uri buildCoordinatesUri({
    required double lat,
    required double lng,
    required ExternalMapApp app,
  }) {
    final point = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    return switch (app) {
      ExternalMapApp.googleMaps => Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': point,
        'travelmode': 'driving',
      }),
      ExternalMapApp.waze => Uri.https('waze.com', '/ul', {
        'll': point,
        'navigate': 'yes',
      }),
    };
  }

  /// Enlace de ruta completa en Google Maps con las paradas pendientes en orden.
  /// Devuelve `null` si no quedan paradas pendientes.
  static ({Uri uri, int omittedCount})? buildFullRouteGoogleMapsUri(
    DriverRoute route,
  ) {
    final pending = route.pendingStops;
    if (pending.isEmpty) return null;

    final selected = pending.take(maxGoogleMapsStops).toList();
    final omittedCount = pending.length - selected.length;
    final destination = _stopTarget(selected.last);
    final waypoints = selected.length > 1
        ? selected
              .sublist(0, selected.length - 1)
              .map(_stopTarget)
              .join('|')
        : null;

    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
      'waypoints': ?waypoints,
      'travelmode': 'driving',
    });
    return (uri: uri, omittedCount: omittedCount);
  }

  static String _stopTarget(DeliveryStop stop) {
    if (stop.hasCoordinates) {
      return '${stop.deliveryLat!.toStringAsFixed(6)},${stop.deliveryLng!.toStringAsFixed(6)}';
    }
    return stop.address;
  }

  Future<bool> openStop(DeliveryStop stop, ExternalMapApp app) =>
      _launchSafely(buildStopUri(stop, app));

  Future<bool> openDepot({
    required double lat,
    required double lng,
    required ExternalMapApp app,
  }) => _launchSafely(buildCoordinatesUri(lat: lat, lng: lng, app: app));

  Future<({bool launched, int omittedCount})> openFullRoute(
    DriverRoute route,
  ) async {
    final built = buildFullRouteGoogleMapsUri(route);
    if (built == null) return (launched: false, omittedCount: 0);
    final launched = await _launchSafely(built.uri);
    return (launched: launched, omittedCount: built.omittedCount);
  }

  Future<bool> _launchSafely(Uri uri) async {
    try {
      return await _launcher(uri);
    } catch (_) {
      return false;
    }
  }
}
