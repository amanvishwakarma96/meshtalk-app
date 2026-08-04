import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';
import 'package:meshtalk_app/features/chat/presentation/chat_screen.dart';

void main() {
  testWidgets('renders messages and sends trimmed input', (tester) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          state: _state(
            status: ChatConnectionStatus.connected,
            messages: <ChatTimelineMessage>[
              ChatTimelineMessage(
                id: 'message-1',
                text: 'hello mesh',
                senderLabel: 'Peer A',
                timestampUtc: DateTime.utc(2026, 8, 4, 10),
                direction: ChatMessageDirection.incoming,
                deliveryStatus: ChatDeliveryStatus.received,
              ),
            ],
          ),
          onSend: (text) async {
            sent = text;
          },
          onRetry: () async {},
          onOpenSettings: () async {},
        ),
      ),
    );

    expect(find.text('hello mesh'), findsOneWidget);
    expect(find.textContaining('Connected to 1 nearby peer'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey<String>('message-input')),
      '  reply nearby  ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('send-button')));
    await tester.pump();

    expect(sent, 'reply nearby');
    expect(find.text('reply nearby'), findsNothing);
  });

  testWidgets('shows an actionable permission-denied state', (tester) async {
    var openedSettings = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          state: _state(status: ChatConnectionStatus.permissionDenied),
          onSend: (_) async {},
          onRetry: () async {},
          onOpenSettings: () async {
            openedSettings = true;
          },
        ),
      ),
    );

    expect(find.text('Bluetooth permission denied'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('send-button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('open-settings-button')),
    );
    await tester.pump();

    expect(openedSettings, isTrue);
  });
}

ChatSessionState _state({
  required ChatConnectionStatus status,
  List<ChatTimelineMessage> messages = const <ChatTimelineMessage>[],
}) {
  return ChatSessionState(
    profile: const LocalProfile(
      deviceId: '550e8400-e29b-41d4-a716-446655440000',
      displayName: 'Trail Phone',
    ),
    status: status,
    statusMessage: status == ChatConnectionStatus.connected
        ? 'Connected to 1 nearby peer over BLE.'
        : 'Bluetooth permission is required for nearby mesh chat.',
    messages: messages,
    peers: status == ChatConnectionStatus.connected
        ? const <dynamic>[]
        : const <dynamic>[],
    pendingCount: 0,
  );
}
