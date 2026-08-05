import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';
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
  late SecureRoom secureRoom;
  late MessageProtector protector;
  late ChatSession session;
  var settingsOpened = false;

  setUp(() async {
    radio = FakeBleRadio();
    transport = FakeChatTransport(radio);
    fallbackTransport = FakeVerifiableChatTransport(
      radio,
      transportId: 'android-nearby',
      forcedAvailability: false,
    );
    diagnosticTransport = null;
    messageStore = FakeMessageStore();
    protector = MessageProtector();
    secureRoom = await _secureRoom();
    settingsOpened = false;
    session = _session(
      radio: radio,
      transport: transport,
      fallback: fallbackTransport,
      store: messageStore,
      room: secureRoom,
      protector: protector,
      openSettings: () async {
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

  test('persists ciphertext and marks it sent after peer recovery', () async {
    await session.initialize();
    await session.send(' hello mesh ');

    expect(session.state.pendingCount, 1);
    expect(
      messageStore.messages.single.deliveryStatus,
      StoredDeliveryStatus.queued,
    );
    expect(
      protector.isProtectedPayload(
        messageStore.messages.single.envelope.payload,
      ),
      isTrue,
    );
    expect(
      session.state.messages.single.protectionStatus,
      MessageProtectionStatus.endToEndEncrypted,
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
    final decrypted = await protector.unprotect(
      envelope: transport.sentMessages.single,
      room: secureRoom,
    );
    expect(utf8.decode(decrypted.clearText), 'hello mesh');
  });

  test('migrates legacy queued plaintext before restoring delivery', () async {
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
    expect(
      session.state.messages.single.protectionStatus,
      MessageProtectionStatus.legacyUnencrypted,
    );
    expect(session.state.pendingCount, 1);
    expect(messageStore.messages.single.envelope.roomId, secureRoom.id);
    expect(
      protector.isProtectedPayload(
        messageStore.messages.single.envelope.payload,
      ),
      isTrue,
    );

    transport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ],
    );
    await _drainEvents();

    final sent = transport.sentMessages.single;
    expect(sent.id, queuedEnvelope.id);
    expect(sent.roomId, secureRoom.id);
    final decrypted = await protector.unprotect(
      envelope: sent,
      room: secureRoom,
    );
    expect(utf8.decode(decrypted.clearText), 'survive restart');
    expect(session.state.pendingCount, 0);
  });

  test('persists and relays authenticated incoming ciphertext once', () async {
    await session.initialize();
    transport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ],
    );
    await _drainEvents();
    final incoming = await _protectedEnvelope(
      protector: protector,
      room: secureRoom,
      id: '550e8400-e29b-41d4-a716-446655440000',
      senderId: 'remote-device',
      text: 'from peer',
      hopLimit: 2,
    );

    transport.emitIncoming(incoming);
    transport.emitIncoming(incoming);
    await _drainEvents();

    expect(session.state.messages.single.text, 'from peer');
    expect(
      session.state.messages.single.protectionStatus,
      MessageProtectionStatus.endToEndEncrypted,
    );
    expect(messageStore.messages.length, 1);
    expect(
      messageStore.messages.single.deliveryStatus,
      StoredDeliveryStatus.received,
    );
    expect(
      protector.isProtectedPayload(
        messageStore.messages.single.envelope.payload,
      ),
      isTrue,
    );
    expect(transport.sentMessages.single.hopLimit, 1);
    final relayed = await protector.unprotect(
      envelope: transport.sentMessages.single,
      room: secureRoom,
    );
    expect(utf8.decode(relayed.clearText), 'from peer');
  });

  test('drops tampered ciphertext and records an encryption error', () async {
    await session.initialize();
    final incoming = await _protectedEnvelope(
      protector: protector,
      room: secureRoom,
      id: '550e8400-e29b-41d4-a716-446655440099',
      senderId: 'remote-device',
      text: 'do not display',
      hopLimit: 1,
    );
    final changed = Uint8List.fromList(incoming.payload);
    changed[changed.length - 1] ^= 0x01;

    transport.emitIncoming(incoming.copyWith(payload: changed));
    await _drainEvents();

    expect(session.state.messages, isEmpty);
    expect(messageStore.messages, isEmpty);
    expect(
      session.state.diagnostics?.lastError,
      contains('authentication failed'),
    );
  });

  test('relays encrypted messages for another room without displaying them',
      () async {
    await session.initialize();
    transport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ],
    );
    await _drainEvents();
    final otherRoom = await _secureRoom(
      roomId: 'anotherSecureRoom1234567',
      keyOffset: 40,
    );
    final incoming = await _protectedEnvelope(
      protector: protector,
      room: otherRoom,
      id: '550e8400-e29b-41d4-a716-446655440088',
      senderId: 'remote-device',
      text: 'relay only',
      hopLimit: 2,
    );

    transport.emitIncoming(incoming);
    await _drainEvents();

    expect(session.state.messages, isEmpty);
    expect(messageStore.messages, isEmpty);
    expect(transport.sentMessages.single.id, incoming.id);
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
      profile: _profile,
      secureRoom: secureRoom,
      messageProtector: protector,
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

  test('records active transport and encrypted room diagnostics', () async {
    await session.initialize();

    final diagnostics = session.state.diagnostics;
    expect(diagnostics, isNotNull);
    expect(diagnostics!.activeTransportId, transport.id);
    expect(diagnostics.activeTransportKind, TransportKind.bleMesh);
    expect(diagnostics.bluetoothAvailability, BleRadioAvailability.ready);
    expect(diagnostics.activeTransportMaxPayloadBytes, 64);
    expect(diagnostics.lastError, isNull);
    expect(session.state.secureRoom.id, secureRoom.id);
    expect(session.state.secureRoom.keyId, secureRoom.keyId);
  });

  test('refreshes transport availability when the app resumes', () async {
    await session.initialize();
    final checksBeforeResume = transport.availabilityChecks;

    await session.onAppResumed();

    expect(transport.availabilityChecks, greaterThan(checksBeforeResume));
  });

  test('flushes encrypted queue through Android Nearby fallback', () async {
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

    final decrypted = await protector.unprotect(
      envelope: fallbackTransport.sentMessages.single,
      room: secureRoom,
    );
    expect(utf8.decode(decrypted.clearText), 'fallback delivery');
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

const LocalProfile _profile = LocalProfile(
  deviceId: 'device-local',
  displayName: 'Trail Phone',
);

ChatSession _session({
  required FakeBleRadio radio,
  required FakeChatTransport transport,
  required FakeChatTransport fallback,
  required FakeMessageStore store,
  required SecureRoom room,
  required MessageProtector protector,
  required Future<void> Function() openSettings,
}) {
  return ChatSession(
    profile: _profile,
    secureRoom: room,
    messageProtector: protector,
    radio: radio,
    bleTransport: transport,
    transportManager: TransportManager(
      transports: <ChatTransport>[transport, fallback],
    ),
    messageStore: store,
    openAppSettings: openSettings,
  );
}

Future<SecureRoom> _secureRoom({
  String roomId = 'secureRoomIdentifier1234',
  int keyOffset = 0,
}) async {
  final key = Uint8List.fromList(
    List<int>.generate(32, (index) => (index + keyOffset) % 256),
  );
  final codec = SecureRoomCodeCodec();
  return SecureRoom(
    id: roomId,
    name: 'Family mesh',
    keyId: await codec.deriveKeyId(key),
    keyBytes: key,
    createdAtUtc: DateTime.utc(2026, 8, 5),
  );
}

Future<MessageEnvelope> _protectedEnvelope({
  required MessageProtector protector,
  required SecureRoom room,
  required String id,
  required String senderId,
  required String text,
  required int hopLimit,
}) {
  return protector.protect(
    envelope: MessageEnvelope(
      id: id,
      senderId: senderId,
      roomId: room.id,
      timestampUtc: DateTime.utc(2026, 8, 5, 12),
      hopLimit: hopLimit,
      payload: Uint8List(0),
    ),
    clearText: Uint8List.fromList(utf8.encode(text)),
    room: room,
  );
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
