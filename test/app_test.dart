import 'package:app_movil_logistica/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la app inicia y muestra la URL de la API', (tester) async {
    await tester.pumpWidget(const LogisticaApp());

    expect(find.text('Logística UTA'), findsOneWidget);
    expect(find.textContaining('API:'), findsOneWidget);
  });
}
