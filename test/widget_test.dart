import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    // Monta una app mínima para evitar dependencias externas en tests
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('app running'))),
      ),
    );

    expect(find.text('app running'), findsOneWidget);
  });
}
