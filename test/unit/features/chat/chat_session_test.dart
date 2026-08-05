import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:meshtalk_app/features/chat/data/chat_session.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';

import '../../../helpers/fake_ble_chat.dart';
import '../../../helpers/fake_message_store.dart';

void main() {
  late FakeBleRadio radio;
  late FakeChatTransport transport;
  late FakeChatTransport fallbackTransport;
  late FakeMessageStore messageStore;
  late ChatSession session;
  var settingsOpened = false;

  setUp(() {
    radio = FakeBleRadio();
    transport = FakeChatTransport(radio);
    fallbackTransport = FakeChatTransport(
      radio,
      transportId: 'fake-android-nearby',
      transportKind: TransportKind.localWifi,
      forcedAvailability: false,
    );
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
    expect(session.state.statusMessage, contains('unverified Android Nearby'));
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
