import 'package:flutter_test/flutter_test.dart';
import 'package:travelalerts/main.dart';

void main() {
  testWidgets('dashboard shows the app name and demo-data warning', (tester) async {
    await tester.pumpWidget(const SuceavaPulseApp());

    expect(find.text('SUCEAVA PULSE'), findsOneWidget);
    expect(find.text('DEMAND RADAR'), findsOneWidget);
    expect(find.textContaining('sosiri demonstrative'), findsOneWidget);
  });

  testWidgets('navigation can open arrivals and settings', (tester) async {
    await tester.pumpWidget(const SuceavaPulseApp());

    await tester.tap(find.text('Sosiri'));
    await tester.pumpAndSettle();
    expect(find.text('Sosiri estimate'), findsOneWidget);

    await tester.tap(find.text('Setări'));
    await tester.pumpAndSettle();
    expect(find.text('Alege ce notificări vrei să primești.'), findsOneWidget);
  });
}
