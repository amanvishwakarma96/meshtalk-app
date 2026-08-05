import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:meshtalk_app/core/transport/transport_runtime_diagnostics.dart';
import 'package:meshtalk_app/features/chat/data/chat_session.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';

import '../../../helpers/fake_ble_chat.dart';
import '../../../helpers/fake_message_store.dart';

void main() {
  late FakeBleRadio radio;
  late FakeChatTransport transport;
  late FakeVerifiableChatTransport fallbackTransport;
  FakeDiagnosticChatTransport? diagnosticTransport;
  late FakeMessageStore messageStore;
  late ChatSession session;
  var settingsOpened = false;

  setUp(() {
    radio = FakeBleRadio();
    transport = FakeChatTransport(radio);
    fallbackTransport = FakeVerifiableChatTransport(
      radio,
      transportId: 'android-nearby',
      forcedAvailability: false,
    );
    diagnosticTransport = null;
    messageStore = FakeMessageStore();
    settingsOpened = false;
    session = ChatSession(
      profile: const LocalProfile(
        deviceId: 'device-local',
        displayName: 'Trail Phone',
      ),
      radio: radio,
      bleTransport: transport,
      transportManager: TransportManager(
        transports: <ChatTransport>[transport, fallbackTransport],
      ),
      messageStore: messageStore,
      openAppSettings: () async {
        settingsOpened = true;
      },
    );
  });

  tearDown(() async {
    await session.close();
    await diagnosticTransport?.close();
    await transport.close();
    await fallbackTransport.close();
    await radio.close();
  });

  test('persists queued sends and marks them sent after peer recovery',
      () async {
    await session.initialize();
    await session.send(' hello mesh ');

    expect(session.state.pendingCount, 1);
    expect(
      messageStore.messages.single.deliveryStatus,
      StoredDeliveryStatus.queued,
    );

    transport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ],
    );
    await _drainEvents();

    expect(session.state.pendingCount, 0);
    expect(
      session.state.messages.single.deliveryStatus,
      ChatDeliveryStatus.sent,
    );
    expect(
      messageStore.messages.single.deliveryStatus,
      StoredDeliveryStatus.sent,
    );
    expect(transport.sentMessages.single.payload, utf8.encode('hello mesh'));
  });

  test('restores history and resumes persisted queued outbound messages',
      () async {
    final queuedEnvelope = MessageEnvelope(
      id: '550e8400-e29b-41d4-a716-446655440001',
      senderId: 'device-local',
      roomId: 'nearby',
      timestampUtc: DateTime.utc(2026, 8, 4, 9),
      hopLimit: 4,
      payload: Uint8List.fromList(utf8.encode('survive restart')),
    );
    await messageStore.upsert(
      StoredChatMessage(
        envelope: queuedEnvelope,
        senderLabel: 'Trail Phone',
        direction: StoredMessageDirection.outgoing,
        deliveryStatus: StoredDeliveryStatus.queued,
      ),
    );

    await session.initialize();

    expect(session.state.messages.single.text, 'survive restart');
    expect(session.state.pendingCount, 1);

    transport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ],
    );
    await _drainEvents();

    expect(transport.sentMessages.single.id, queuedEnvelope.id);
    expect(session.state.pendingCount, 0);
    expect(
      messageStore.messages.single.deliveryStatus,
      StoredDeliveryStatus.sent,
    );
  });

  test('persists and relays a new incoming message exactly once', () async {
    await session.initialize();
    transport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ],
    );
    await _drainEvents();
    final incoming = MessageEnvelope(
      id: '550e8400-e29b-41d4-a716-446655440000',
      senderId: 'remote-device',
      roomId: 'nearby',
      timestampUtc: DateTime.utc(2026, 8, 4),
      hopLimit: 2,
      payload: Uint8List.fromList(utf8.encode('from peer')),
    );

    transport.emitIncoming(incoming);
    transport.emitIncoming(incoming);
    await _drainEvents();

    expect(session.state.messages.single.text, 'from peer');
    expect(messageStore.messages.length, 1);
    expect(
      messageStore.messages.single.deliveryStatus,
      StoredDeliveryStatus.received,
    );
    expect(transport.sentMessages.single.hopLimit, 1);
  });

  test('shows permission recovery when BLE remains unauthorized', () async {
    radio.currentAvailability = BleRadioAvailability.unauthorized;

    await session.initialize();

    expect(session.state.status, ChatConnectionStatus.permissionDenied);
    await session.openSettings();
    expect(settingsOpened, isTrue);
  });

  test('activates Android Nearby when Bluetooth is off', () async {
    radio.currentAvailability = BleRadioAvailability.poweredOff;
    fallbackTransport.forcedAvailability = true;

    await session.initialize();

    expect(session.state.status, ChatConnectionStatus.scanning);
    expect(session.state.activeTransportKind, TransportKind.localWifi);
    expect(session.state.statusMessage, contains('Android Nearby Connections'));

    fallbackTransport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-wifi', displayName: 'Nearby Peer'),
      ],
    );
    await _drainEvents();

    expect(session.state.status, ChatConnectionStatus.connected);
    expect(session.state.activeTransportKind, TransportKind.localWifi);
    expect(session.state.statusMessage, contains('verified Android Nearby'));
  });

  test('labels iOS Multipeer and records native runtime errors', () async {
    await session.close();
    radio.currentAvailability = BleRadioAvailability.poweredOff;
    diagnosticTransport = FakeDiagnosticChatTransport(
      radio,
      transportId: 'ios-multipeer',
      forcedAvailability: true,
    );
    final iosFallback = diagnosticTransport!;
    session = ChatSession(
      profile: const LocalProfile(
        deviceId: 'device-local',
        displayName: 'Trail Phone',
      ),
      radio: radio,
      bleTransport: transport,
      transportManager: TransportManager(
        transports: <ChatTransport>[transport, iosFallback],
      ),
      messageStore: messageStore,
      openAppSettings: () async {},
    );

    await session.initialize();

    expect(session.state.activeTransportKind, TransportKind.localWifi);
    expect(session.state.statusMessage, contains('iOS Multipeer Connectivity'));

    iosFallback.emitRuntimeError('iOS local-network discovery stopped.');
    await _drainEvents();

    expect(
      session.state.diagnostics?.lastError,
      'iOS local-network discovery stopped.',
    );
    expect(
      session.state.statusMessage,
      'iOS local-network discovery stopped.',
    );
  });

  test('routes matching-code approval to the active verification transport',
      () async {
    radio.currentAvailability = BleRadioAvailability.poweredOff;
    fallbackTransport.forcedAvailability = true;
    await session.initialize();
    const request = PeerVerificationRequest(
      transportId: 'android-nearby',
      endpointId: 'endpoint-a',
      peerId: 'peer-a',
      displayName: 'Peer A',
      authenticationToken: '4721',
      isIncomingConnection: true,
    );

    fallbackTransport.emitVerification(request);
    await _drainEvents();

    expect(
      session.state.verificationRequests,
      <PeerVerificationRequest>[request],
    );
    expect(
      session.state.statusMessage,
      contains('waiting for code verification'),
    );

    await session.approvePeer(request);
    await _drainEvents();

    expect(fallbackTransport.approvedEndpointIds, <String>['endpoint-a']);
    expect(session.state.verificationRequests, isEmpty);
  });

  test('routes rejection and removes the verification request', () async {
    radio.currentAvailability = BleRadioAvailability.poweredOff;
    fallbackTransport.forcedAvailability = true;
    await session.initialize();
    const request = PeerVerificationRequest(
      transportId: 'android-nearby',
      endpointId: 'endpoint-b',
      peerId: 'peer-b',
      displayName: 'Peer B',
      authenticationToken: '8391',
      isIncomingConnection: false,
    );

    fallbackTransport.emitVerification(request);
    await _drainEvents();
    await session.rejectPeer(request);
    await _drainEvents();

    expect(fallbackTransport.rejectedEndpointIds, <String>['endpoint-b']);
    expect(session.state.verificationRequests, isEmpty);
  });

  test('records active transport diagnostics', () async {
    await session.initialize();

    final diagnostics = session.state.diagnostics;
    expect(diagnostics, isNotNull);
    expect(diagnostics!.activeTransportId, transport.id);
    expect(diagnostics.activeTransportKind, TransportKind.bleMesh);
    expect(diagnostics.bluetoothAvailability, BleRadioAvailability.ready);
    expect(diagnostics.activeTransportMaxPayloadBytes, 64);
    expect(diagnostics.lastError, isNull);
  });

  test('refreshes transport availability when the app resumes', () async {
    await session.initialize();
    final checksBeforeResume = transport.availabilityChecks;

    await session.onAppResumed();

    expect(transport.availabilityChecks, greaterThan(checksBeforeResume));
  });

  test('flushes the durable queue through the Android Nearby fallback',
      () async {
    radio.currentAvailability = BleRadioAvailability.poweredOff;
    fallbackTransport.forcedAvailability = true;
    await session.initialize();
    await session.send('fallback delivery');

    expect(session.state.pendingCount, 1);

    fallbackTransport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-wifi', displayName: 'Nearby Peer'),
      ],
    );
    await _drainEvents();

    expect(
      fallbackTransport.sentMessages.single.payload,
      utf8.encode('fallback delivery'),
    );
    expect(session.state.pendingCount, 0);
    expect(
      messageStore.messages.single.deliveryStatus,
      StoredDeliveryStatus.sent,
    );
  });

  test('upgrades from Android Nearby to BLE when Bluetooth recovers', () async {
    radio.currentAvailability = BleRadioAvailability.poweredOff;
    fallbackTransport.forcedAvailability = true;
    await session.initialize();
    fallbackTransport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-wifi', displayName: 'Nearby Peer'),
      ],
    );
    await _drainEvents();
    expect(session.state.activeTransportKind, TransportKind.localWifi);

    radio.emitAvailability(BleRadioAvailability.ready);
    await _drainEvents();

    expect(session.state.activeTransportKind, TransportKind.bleMesh);
    expect(session.state.status, ChatConnectionStatus.scanning);
    expect(fallbackTransport.connected, isFalse);
  });
}

Future<void> _drainEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class FakeDiagnosticChatTransport extends FakeChatTransport
    implements TransportRuntimeDiagnostics {
  FakeDiagnosticChatTransport(
    super.radio, {
    required super.transportId,
    super.forcedAvailability,
  }) : super(transportKind: TransportKind.localWifi);

  final StreamController<TransportRuntimeError> _runtimeErrorController =
      StreamController<TransportRuntimeError>.broadcast();

  @override
  Stream<TransportRuntimeError> get runtimeErrors =>
      _runtimeErrorController.stream;

  void emitRuntimeError(String message) {
    _runtimeErrorController.add(
      TransportRuntimeError(transportId: id, message: message),
    );
  }

  @override
  Future<void> close() async {
    await super.close();
    await _runtimeErrorController.close();
  }
}
