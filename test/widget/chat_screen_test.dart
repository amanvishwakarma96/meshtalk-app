import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';
import 'package:meshtalk_app/features/chat/domain/transport_diagnostics.dart';
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
          onUpdateDisplayName: (_) async {},
          onApprovePeer: (_) async {},
          onRejectPeer: (_) async {},
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

  testWidgets('shows an actionable Bluetooth permission-denied state',
      (tester) async {
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
          onUpdateDisplayName: (_) async {},
          onApprovePeer: (_) async {},
          onRejectPeer: (_) async {},
        ),
      ),
    );

    expect(find.text('Bluetooth permission denied'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('open-settings-button')),
    );
    await tester.pump();

    expect(openedSettings, isTrue);
  });

  testWidgets('labels a code-verified Android Nearby connection',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          state: _state(
            status: ChatConnectionStatus.connected,
            activeTransportKind: TransportKind.localWifi,
          ),
          onSend: (_) async {},
          onRetry: () async {},
          onOpenSettings: () async {},
          onUpdateDisplayName: (_) async {},
          onApprovePeer: (_) async {},
          onRejectPeer: (_) async {},
        ),
      ),
    );

    expect(find.text('Verified Android Nearby connection'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('nearby-verified-label')),
      findsOneWidget,
    );
    expect(find.textContaining('verified Android Nearby'), findsWidgets);
  });

  testWidgets('shows the matching code and approves a Nearby peer',
      (tester) async {
    PeerVerificationRequest? approved;
    const request = PeerVerificationRequest(
      transportId: 'android-nearby',
      endpointId: 'endpoint-a',
      peerId: 'peer-a',
      displayName: 'Aman Phone',
      authenticationToken: '4721',
      isIncomingConnection: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          state: _state(
            status: ChatConnectionStatus.scanning,
            activeTransportKind: TransportKind.localWifi,
            verificationRequests: const <PeerVerificationRequest>[request],
          ),
          onSend: (_) async {},
          onRetry: () async {},
          onOpenSettings: () async {},
          onUpdateDisplayName: (_) async {},
          onApprovePeer: (value) async {
            approved = value;
          },
          onRejectPeer: (_) async {},
        ),
      ),
    );

    expect(find.text('Verify Aman Phone'), findsOneWidget);
    expect(find.text('4721'), findsOneWidget);
    expect(find.text('Verify Nearby peer'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('approve-peer-endpoint-a')),
    );
    await tester.pump();

    expect(approved, request);
  });

  testWidgets('routes rejection for a pending Nearby peer', (tester) async {
    PeerVerificationRequest? rejected;
    const request = PeerVerificationRequest(
      transportId: 'android-nearby',
      endpointId: 'endpoint-b',
      peerId: 'peer-b',
      displayName: 'Unknown Phone',
      authenticationToken: '8391',
      isIncomingConnection: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          state: _state(
            status: ChatConnectionStatus.scanning,
            activeTransportKind: TransportKind.localWifi,
            verificationRequests: const <PeerVerificationRequest>[request],
          ),
          onSend: (_) async {},
          onRetry: () async {},
          onOpenSettings: () async {},
          onUpdateDisplayName: (_) async {},
          onApprovePeer: (_) async {},
          onRejectPeer: (value) async {
            rejected = value;
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reject-peer-endpoint-b')),
    );
    await tester.pump();

    expect(rejected, request);
  });

  testWidgets('opens diagnostics and refreshes the transport', (tester) async {
    var refreshed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          state: _state(status: ChatConnectionStatus.connected),
          onSend: (_) async {},
          onRetry: () async {
            refreshed = true;
          },
          onOpenSettings: () async {},
          onUpdateDisplayName: (_) async {},
          onApprovePeer: (_) async {},
          onRejectPeer: (_) async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('diagnostics-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('transport-diagnostics-dialog')),
      findsOneWidget,
    );
    expect(find.text('Bluetooth LE mesh'), findsOneWidget);
    expect(find.text('64 bytes'), findsOneWidget);
    expect(find.text('None'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('diagnostics-refresh-button')),
    );
    await tester.pumpAndSettle();

    expect(refreshed, isTrue);
    expect(
      find.byKey(const ValueKey<String>('transport-diagnostics-dialog')),
      findsNothing,
    );
  });

  testWidgets('opens settings for denied Android Nearby permissions',
      (tester) async {
    var openedSettings = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          state: _state(
            status: ChatConnectionStatus.localNetworkPermissionDenied,
          ),
          onSend: (_) async {},
          onRetry: () async {},
          onOpenSettings: () async {
            openedSettings = true;
          },
          onUpdateDisplayName: (_) async {},
          onApprovePeer: (_) async {},
          onRejectPeer: (_) async {},
        ),
      ),
    );

    expect(find.text('Nearby permission denied'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('open-settings-button')),
    );
    await tester.pump();

    expect(openedSettings, isTrue);
  });

  testWidgets('validates and saves an edited local display name',
      (tester) async {
    String? updatedName;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          state: _state(status: ChatConnectionStatus.connected),
          onSend: (_) async {},
          onRetry: () async {},
          onOpenSettings: () async {},
          onUpdateDisplayName: (displayName) async {
            updatedName = displayName;
          },
          onApprovePeer: (_) async {},
          onRejectPeer: (_) async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('profile-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('display-name-input')),
      'Aman Phone',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('save-profile-button')),
    );
    await tester.pumpAndSettle();

    expect(updatedName, 'Aman Phone');
  });
}

ChatSessionState _state({
  required ChatConnectionStatus status,
  List<ChatTimelineMessage> messages = const <ChatTimelineMessage>[],
  TransportKind? activeTransportKind,
  List<PeerVerificationRequest> verificationRequests =
      const <PeerVerificationRequest>[],
}) {
  final connected = status == ChatConnectionStatus.connected;
  final localWifi = activeTransportKind == TransportKind.localWifi;
  final transportKind = activeTransportKind ?? TransportKind.bleMesh;
  return ChatSessionState(
    profile: const LocalProfile(
      deviceId: '550e8400-e29b-41d4-a716-446655440000',
      displayName: 'Trail Phone',
    ),
    status: status,
    statusMessage: connected
        ? localWifi
            ? 'Connected to 1 nearby peer over verified Android Nearby.'
            : 'Connected to 1 nearby peer over BLE.'
        : verificationRequests.isNotEmpty
            ? '1 nearby peer waiting for code verification.'
            : status == ChatConnectionStatus.localNetworkPermissionDenied
                ? 'Nearby devices permission is required for the Android fallback.'
                : 'Bluetooth permission is required for nearby mesh chat.',
    messages: messages,
    peers: connected
        ? const <NearbyPeer>[
            NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
          ]
        : const <NearbyPeer>[],
    pendingCount: 0,
    activeTransportKind: activeTransportKind,
    verificationRequests: verificationRequests,
    diagnostics: TransportDiagnosticsSnapshot(
      bluetoothAvailability: BleRadioAvailability.ready,
      refreshedAtUtc: DateTime.utc(2026, 8, 5, 9),
      activeTransportId: localWifi ? 'android-nearby' : 'fake-ble',
      activeTransportKind: transportKind,
      activeTransportMaxPayloadBytes: localWifi ? 32 * 1024 : 64,
    ),
  );
}
