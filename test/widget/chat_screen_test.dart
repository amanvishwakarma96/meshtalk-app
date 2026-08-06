import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/identity_trust_store.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';
import 'package:meshtalk_app/features/chat/domain/transport_diagnostics.dart';
import 'package:meshtalk_app/features/chat/presentation/chat_screen.dart';

void main() {
  testWidgets('renders signed encrypted messages and sends trimmed input',
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
              identityStatus: MessageIdentityStatus.verified,
            ),
          ],
        ),
        onSend: (text) async {
          sent = text;
        },
      ),
    );

    expect(find.text('hello mesh'), findsOneWidget);
    expect(find.textContaining('Signed device identities'), findsOneWidget);
    expect(find.text('E2EE · verified sender identity'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('e2ee-room-notice')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('message-input')),
      '  reply nearby  ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('send-button')));
    await tester.pump();

    expect(sent, 'reply nearby');
    expect(find.text('reply nearby'), findsNothing);
  });

  testWidgets('labels unsigned legacy history', (tester) async {
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
              identityStatus: MessageIdentityStatus.legacyUnsigned,
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
    await tester.tap(
      find.byKey(const ValueKey<String>('approve-peer-endpoint-a')),
    );
    await tester.pump();

    expect(approved, request);
  });

  testWidgets('opens identity dialog and verifies a first-seen fingerprint',
      (tester) async {
    TrustedIdentitySummary? verified;
    final identity = _trustedIdentity();
    await tester.pumpWidget(
      _app(
        state: _state(
          status: ChatConnectionStatus.connected,
          trustedIdentities: <TrustedIdentitySummary>[identity],
        ),
        onVerifyIdentity: (value) async {
          verified = value;
        },
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('trusted-identities-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('trusted-identities-dialog')),
      findsOneWidget,
    );
    expect(find.text('LOCA-LKEY'), findsOneWidget);
    expect(find.text(identity.fingerprint), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey<String>('verify-identity-${identity.deviceId}')),
    );
    await tester.pumpAndSettle();

    expect(verified, identity);
  });

  testWidgets('surfaces an identity change and approves the pending key',
      (tester) async {
    TrustedIdentitySummary? approved;
    final changed = _trustedIdentity(
      pendingKeyId: 'pendingK90_',
      changedAtUtc: DateTime.utc(2026, 8, 6, 7),
    );
    await tester.pumpWidget(
      _app(
        state: _state(
          status: ChatConnectionStatus.connected,
          trustedIdentities: <TrustedIdentitySummary>[changed],
        ),
        onAcceptIdentityChange: (value) async {
          approved = value;
        },
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('identity-change-warning')),
      findsOneWidget,
    );
    expect(find.textContaining('1 sender identity change blocked'),
        findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('review-identity-change-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Identity changed'), findsOneWidget);
    expect(find.text(changed.pendingFingerprint!), findsOneWidget);

    final approve = find.byKey(
      ValueKey<String>('accept-identity-change-${changed.deviceId}'),
    );
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();

    expect(approved, changed);
  });

  testWidgets('routes rejection for a changed identity', (tester) async {
    TrustedIdentitySummary? rejected;
    final changed = _trustedIdentity(
      pendingKeyId: 'pendingK90_',
      changedAtUtc: DateTime.utc(2026, 8, 6, 7),
    );
    await tester.pumpWidget(
      _app(
        state: _state(
          status: ChatConnectionStatus.connected,
          trustedIdentities: <TrustedIdentitySummary>[changed],
        ),
        onRejectIdentityChange: (value) async {
          rejected = value;
        },
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('trusted-identities-button')),
    );
    await tester.pumpAndSettle();
    final reject = find.byKey(
      ValueKey<String>('reject-identity-change-${changed.deviceId}'),
    );
    await tester.ensureVisible(reject);
    await tester.tap(reject);
    await tester.pumpAndSettle();

    expect(rejected, changed);
  });

  testWidgets('opens diagnostics with encryption and identity state',
      (tester) async {
    var refreshed = false;
    await tester.pumpWidget(
      _app(
        state: _state(
          status: ChatConnectionStatus.connected,
          trustedIdentities: <TrustedIdentitySummary>[_trustedIdentity()],
        ),
        onRetry: () async {
          refreshed = true;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('diagnostics-button')));
    await tester.pumpAndSettle();

    expect(find.text('XChaCha20-Poly1305 group E2EE'), findsOneWidget);
    expect(find.text('Ed25519 protocol v2'), findsOneWidget);
    expect(find.text('LOCA-LKEY'), findsOneWidget);
    expect(find.text('Bluetooth LE mesh'), findsOneWidget);
    expect(find.text('64 bytes'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('diagnostics-refresh-button')),
    );
    await tester.pumpAndSettle();

    expect(refreshed, isTrue);
  });

  testWidgets('creates and joins encrypted rooms', (tester) async {
    String? roomName;
    String? roomCode;
    await tester.pumpWidget(
      _app(
        state: _state(status: ChatConnectionStatus.connected),
        onCreateRoom: (name) async {
          roomName = name;
        },
        onJoinRoom: (code) async {
          roomCode = code;
        },
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('secure-room-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('room-name-input')),
      'Private family',
    );
    final createButton =
        find.byKey(const ValueKey<String>('create-room-button'));
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(roomName, 'Private family');

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
  Future<void> Function(TrustedIdentitySummary)? onVerifyIdentity,
  Future<void> Function(TrustedIdentitySummary)? onAcceptIdentityChange,
  Future<void> Function(TrustedIdentitySummary)? onRejectIdentityChange,
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
      onVerifyIdentity: onVerifyIdentity ?? (_) async {},
      onAcceptIdentityChange: onAcceptIdentityChange ?? (_) async {},
      onRejectIdentityChange: onRejectIdentityChange ?? (_) async {},
    ),
  );
}

ChatSessionState _state({
  required ChatConnectionStatus status,
  List<ChatTimelineMessage> messages = const <ChatTimelineMessage>[],
  TransportKind? activeTransportKind,
  List<PeerVerificationRequest> verificationRequests =
      const <PeerVerificationRequest>[],
  List<TrustedIdentitySummary> trustedIdentities =
      const <TrustedIdentitySummary>[],
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
    localIdentity: DeviceIdentitySummary(
      deviceId: '550e8400-e29b-41d4-a716-446655440000',
      keyId: 'localKey90_',
      createdAtUtc: DateTime.utc(2026, 8, 6),
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
    trustedIdentities: trustedIdentities,
    diagnostics: TransportDiagnosticsSnapshot(
      bluetoothAvailability: BleRadioAvailability.ready,
      refreshedAtUtc: DateTime.utc(2026, 8, 5, 9),
      activeTransportId: localWifi ? 'android-nearby' : 'fake-ble',
      activeTransportKind: transportKind,
      activeTransportMaxPayloadBytes: localWifi ? 32 * 1024 : 64,
    ),
  );
}

TrustedIdentitySummary _trustedIdentity({
  String? pendingKeyId,
  DateTime? changedAtUtc,
}) {
  return TrustedIdentitySummary(
    deviceId: 'remote-device',
    keyId: 'remoteKey90_',
    trustLevel: IdentityTrustLevel.seen,
    firstSeenAtUtc: DateTime.utc(2026, 8, 6, 6),
    lastSeenAtUtc: DateTime.utc(2026, 8, 6, 6, 5),
    pendingKeyId: pendingKeyId,
    changedAtUtc: changedAtUtc,
  );
}
