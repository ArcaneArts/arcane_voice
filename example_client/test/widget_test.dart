import 'package:example_client/call_screen.dart';
import 'package:arcane_voice/arcane_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Call screen renders idle state', (WidgetTester tester) async {
    CallSessionController controller = CallSessionController(
      serverUrl: "ws://127.0.0.1:8080/ws/realtime",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArcanaCallScreen(controller: controller),
      ),
    );

    expect(find.text('Arcana Voice Proxy'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(
      find.textContaining('ws://127.0.0.1:8080/ws/realtime'),
      findsOneWidget,
    );

    controller.dispose();
  });
}
