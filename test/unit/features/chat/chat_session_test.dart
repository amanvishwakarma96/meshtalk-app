import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:meshtalk_app/features/chat/data/chat_session.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';

void main() {
  late FakeBleRadio radio;
  late FakeChatTransport transport;
  late ChatSession session;
  var settingsOpened = false;

  setUp(() {
    radio = FakeBleRadio();
    transport = FakeChatTransport(radio);
    settingsOpened = false;
    session = ChatSession(
      profile: const LocalProfile(
        deviceId: 'device-local',
        displayName: 'Trail Phone',
      ),
      radio: radio,
      bleTransport: transport,
      transportManager: TransportManager(
        transports: <ChatTransport>[transport],
      ),
      openAppSettings: () async {
        settingsOpened = true;
      },
    );
  });

  tearDown(() async {
    await session.close();
    await transport.close();
    await radio.close();
  });

  test('starts scanning and flushes a queued message when a peer connects',
      () async {
    await session.initialize();
    expect(session.state.status, ChatConnectionStatus.scanning);

    await session.send(' hello mesh ');
    expect(session.state.pendingCount, 1);
    expect(
      session.state.messages.single.deliveryStatus,
      ChatDeliveryStatus.queued,
    );

    transport.emitPeers(
      const <NearbyPeer>[
        NearbyPeer(id: 'peer-a', displayName: 'Peer A'),
      ],
    );
    await _drainEvents();

    expect(session.state.status, ChatConnectionStatus.connected);
    expect(session.state.pendingCount, 0);
    expect(
      session.state.messages.single.deliveryStatus,
      ChatDeliveryStatus.sent,
    );
    expect(transport.sentMessages.single.payload, utf8.encode('hello mesh'));
  });

  test('delivers and relays a new incoming message exactly once', () async {
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

    expect(session.state.messages.length, 1);
    expect(session.state.messages.single.text, 'from peer');
    expect(transport.sentMessages.length, 1);
    expect(transport.sentMessages.single.id, incoming.id);
    expect(transport.sentMessages.single.hopLimit, 1);
  });

  test('shows permission recovery when BLE remains unauthorized', () async {
    radio.currentAvailability = BleRadioAvailability.unauthorized;

    await session.initialize();

    expect(session.state.status, ChatConnectionStatus.permissionDenied);
    expect(session.state.canOpenSettings, isTrue);
    await session.openSettings();
    expect(settingsOpened, isTrue);
  });
}

Future<void> _drainEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class FakeBleRadio implements BleMeshRadio {
  final StreamController<BleRadioAvailability> _availabilityController =
      StreamController<BleRadioAvailability>.broadcast();
  final StreamController<Uint8List> _frameController =
      StreamController<Uint8List>.broadcast();
  final StreamController<List<BleRadioPeer>> _peerController =
      StreamController<List<BleRadioPeer>>.broadcast();

  BleRadioAvailability currentAvailability = BleRadioAvailability.ready;

  @override
  BleRadioAvailability get availability => currentAvailability;

  @override
  Stream<BleRadioAvailability> get availabilityChanges =>
      _availabilityController.stream;

  @override
  Stream<List<BleRadioPeer>> get connectedPeers => _peerController.stream;

  @override
  Stream<Uint8List> get incomingFrames => _frameController.stream;

  @override
  int get maximumFrameBytes => 64;

  @override
  Future<void> sendFrame(Uint8List frame) async {}

  @override
  Future<void> start() async {
    if (currentAvailability != BleRadioAvailability.ready) {
      throw StateError('BLE unavailable');
    }
  }

  @override
  Future<void> stop() async {}

  Future<void> close() async {
    await _availabilityController.close();
    await _frameController.close();
    await _peerController.close();
  }
}

class FakeChatTransport implements ChatTransport {
  FakeChatTransport(this.radio);

  final FakeBleRadio radio;
  final StreamController<MessageEnvelope> _incomingController =
      StreamController<MessageEnvelope>.broadcast();
  final StreamController<List<NearbyPeer>> _peerController =
      StreamController<List<NearbyPeer>>.broadcast();
  final List<MessageEnvelope> sentMessages = <MessageEnvelope>[];
  List<NearbyPeer> _peers = const <NearbyPeer>[];
  bool _connected = false;

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        supportsRelay: true,
        isOffline: true,
        maxPayloadBytes: 64,
      );

  @override
  String get id => 'fake-ble';

  @override
  Stream<MessageEnvelope> get incomingMessages => _incomingController.stream;

  @override
  TransportKind get kind => TransportKind.bleMesh;

  @override
  Stream<List<NearbyPeer>> get nearbyPeers => _peerController.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    await radio.start();
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<bool> isAvailable() async {
    return radio.availability == BleRadioAvailability.ready;
  }

  @override
  Future<void> send(MessageEnvelope message) async {
    if (_peers.isEmpty) {
      throw StateError('No peers');
    }
    sentMessages.add(message);
  }

  void emitPeers(List<NearbyPeer> peers) {
    _peers = List<NearbyPeer>.unmodifiable(peers);
    _peerController.add(_peers);
  }

  void emitIncoming(MessageEnvelope message) {
    _incomingController.add(message);
  }

  Future<void> close() async {
    await _incomingController.close();
    await _peerController.close();
  }
}
