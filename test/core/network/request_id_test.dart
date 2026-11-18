import 'dart:math';

import 'package:app_movil_logistica/core/network/request_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('genera UUID v4 válidos para el servidor', () {
    for (var i = 0; i < 200; i++) {
      expect(newRequestId(), matches(uuidV4));
    }
  });

  test('cada solicitud nueva tiene un id distinto', () {
    final ids = {for (var i = 0; i < 500; i++) newRequestId()};
    expect(ids, hasLength(500));
  });

  test('con la misma semilla es reproducible (solo para pruebas)', () {
    expect(newRequestId(Random(7)), newRequestId(Random(7)));
  });
}
