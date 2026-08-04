import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/features/chat/presentation/chat_screen.dart';

void main() {
  testWidgets('renders messages and sends trimmed input', (tester) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          messages: const <String>['hello mesh'],
          onSend: (text) async {
            sent = text;
          },
        ),
      ),
    );

    expect(find.text('hello mesh'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('message-input')),
      '  reply nearby  ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('send-button')));
    await tester.pump();

    expect(sent, 'reply nearby');
    expect(find.text('reply nearby'), findsNothing);
  });
}
