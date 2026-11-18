import 'dart:math';

final _random = Random.secure();

/// UUID v4 para identificar una mutación ante el servidor. Repetir la misma
/// solicitud con el mismo id es idempotente; nunca se reutiliza para una
/// solicitud distinta.
String newRequestId([Random? random]) {
  final source = random ?? _random;
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // versión 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante RFC 4122
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
