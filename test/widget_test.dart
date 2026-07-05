import 'package:flutter_test/flutter_test.dart';

import 'package:shakal/main.dart';

void main() {
  testWidgets('App starts without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const ShakalApp());
    await tester.pump();
    expect(find.byType(ShakalApp), findsOneWidget);
  });
}
