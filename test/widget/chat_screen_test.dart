import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';
import 'package:meshtalk_app/features/chat/domain/transport_diagnostics.dart';
import 'package:meshtalk_app/features/chat/presentation/chat_screen.dart';

void main() {
  testWidgets('renders encrypted messages and sends trimmed input',
      (tester) async {
    String? sent;
    await tester.pumpWidget(
      _app(
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
              protectionStatus: MessageProtectionStatus.endToEndEncrypted,
            ),
          ],
        ),
        onSend: (text) async {
          sent = text;
        },
      ),
    );

    expect(find.text('hello mesh'), findsOneWidget);
    expect(find.text('end-to-end encrypted'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('e2ee-room-notice')),
      findsOneWidget,
    );
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

  testWidgets('labels legacy unencrypted history', (tester) async {
    await tester.pumpWidget(
      _app(
        state: _state(
          status: ChatConnectionStatus.connected,
          messages: <ChatTimelineMessage>[
            ChatTimelineMessage(
              id: 'legacy-1',
              text: 'older local message',
              senderLabel: 'Trail Phone',
              timestampUtc: DateTime.utc(2026, 8, 4),
              direction: ChatMessageDirection.outgoing,
              deliveryStatus: ChatDeliveryStatus.sent,
              protectionStatus: MessageProtectionStatus.legacyUnencrypted,
            ),
          ],
        ),
      ),
    );

    expect(find.text('older local message'), findsOneWidget);
    expect(find.text('legacy unencrypted history'), findsOneWidget);
  });

  testWidgets('shows an actionable Bluetooth permission-denied state',
      (tester) async {
    var openedSettings = false;
    await tester.pumpWidget(
      _app(
        state: _state(status: ChatConnectionStatus.permissionDenied),
        onOpenSettings: () async {
          openedSettings = true;
        },
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
      _app(
        state: _state(
          status: ChatConnectionStatus.connected,
          activeTransportKind: TransportKind.localWifi,
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
      _app(
        state: _state(
          status: ChatConnectionStatus.scanning,
          activeTransportKind: TransportKind.localWifi,
          verificationRequests: const <PeerVerificationRequest>[request],
        ),
        onApprovePeer: (value) async {
          approved = value;
        },
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
      _app(
        state: _state(
          status: ChatConnectionStatus.scanning,
          activeTransportKind: TransportKind.localWifi,
          verificationRequests: const <PeerVerificationRequest>[request],
        ),
        onRejectPeer: (value) async {
          rejected = value;
        },
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('reject-peer-endpoint-b')),
    );
    await tester.pump();

    expect(rejected, request);
  });

  testWidgets('opens diagnostics with encryption state and refreshes',
      (tester) async {
    var refreshed = false;
    await tester.pumpWidget(
      _app(
        state: _state(status: ChatConnectionStatus.connected),
        onRetry: () async {
          refreshed = true;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('diagnostics-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('transport-diagnostics-dialog')),
      findsOneWidget,
    );
    expect(find.text('XChaCha20-Poly1305 group E2EE'), findsOneWidget);
    expect(find.text('Family mesh'), findsWidgets);
    expect(find.text('ABCD-EFGH'), findsWidgets);
    expect(find.text('Bluetooth LE mesh'), findsOneWidget);
    expect(find.text('64 bytes'), findsOneWidget);

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

  testWidgets('creates a new encrypted room from the room dialog',
      (tester) async {
    String? roomName;
    await tester.pumpWidget(
      _app(
        state: _state(status: ChatConnectionStatus.connected),
        onCreateRoom: (name) async {
          roomName = name;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('secure-room-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('secure-room-dialog')),
      findsOneWidget,
    );
    expect(find.text('Key fingerprint: ABCD-EFGH'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('room-name-input')),
      'Private family',
    );
    await tester.tap(find.byKey(const ValueKey<String>('create-room-button')));
    await tester.pumpAndSettle();

    expect(roomName, 'Private family');
    expect(
      find.byKey(const ValueKey<String>('secure-room-dialog')),
      findsNothing,
    );
  });

  testWidgets('joins an encrypted room from a pasted code', (tester) async {
    String? roomCode;
    await tester.pumpWidget(
      _app(
        state: _state(status: ChatConnectionStatus.connected),
        onJoinRoom: (code) async {
          roomCode = code;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('secure-room-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('room-code-input')),
      'MT1.example-room-code',
    );
    await tester.tap(find.byKey(const ValueKey<String>('join-room-button')));
    await tester.pumpAndSettle();

    expect(roomCode, 'MT1.example-room-code');
  });

  testWidgets('opens settings for denied local-network permissions',
      (tester) async {
    var openedSettings = false;
    await tester.pumpWidget(
      _app(
        state: _state(
          status: ChatConnectionStatus.localNetworkPermissionDenied,
        ),
        onOpenSettings: () async {
          openedSettings = true;
        },
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
      _app(
        state: _state(status: ChatConnectionStatus.connected),
        onUpdateDisplayName: (displayName) async {
          updatedName = displayName;
        },
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

Widget _app({
  required ChatSessionState state,
  Future<void> Function(String)? onSend,
  Future<void> Function()? onRetry,
  Future<void> Function()? onOpenSettings,
  Future<void> Function(String)? onUpdateDisplayName,
  Future<void> Function(PeerVerificationRequest)? onApprovePeer,
  Future<void> Function(PeerVerificationRequest)? onRejectPeer,
  Future<String> Function()? onExportRoomCode,
  Future<void> Function(String)? onCreateRoom,
  Future<void> Function(String)? onJoinRoom,
}) {
  return MaterialApp(
    home: ChatScreen(
      state: state,
      onSend: onSend ?? (_) async {},
      onRetry: onRetry ?? () async {},
      onOpenSettings: onOpenSettings ?? () async {},
      onUpdateDisplayName: onUpdateDisplayName ?? (_) async {},
      onApprovePeer: onApprovePeer ?? (_) async {},
      onRejectPeer: onRejectPeer ?? (_) async {},
      onExportRoomCode: onExportRoomCode ?? () async => 'MT1.room-code',
      onCreateRoom: onCreateRoom ?? (_) async {},
      onJoinRoom: onJoinRoom ?? (_) async {},
    ),
  );
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
    secureRoom: SecureRoomSummary(
      id: 'secureRoomIdentifier1234',
      name: 'Family mesh',
      keyId: 'abcdEFgh12_',
      createdAtUtc: DateTime.utc(2026, 8, 5),
    ),
    status: status,
    statusMessage: connected
        ? localWifi
            ? 'Connected to 1 nearby peer over verified Android Nearby.'
            : 'Connected to 1 nearby peer over BLE.'
        : verificationRequests.isNotEmpty
            ? '1 nearby peer waiting for code verification.'
            : status == ChatConnectionStatus.localNetworkPermissionDenied
                ? 'Nearby devices permission is required for the local fallback.'
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
