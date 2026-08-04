import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/transport/ble_transport.dart';

void main() {
  late FakeBleMeshRadio radio;
  late BleTransport transport;

  setUp(() {
    radio = FakeBleMeshRadio(maximumFrameBytes: 64);
    transport = BleTransport(radio: radio);
  });

  tearDown(() async {
    await transport.disconnect();
    await radio.dispose();
  });

  test('reports availability from the BLE radio', () async {
    expect(await transport.isAvailable(), isTrue);

    radio.currentAvailability = BleRadioAvailability.poweredOff;

    expect(await transport.isAvailable(), isFalse);
  });

  test('chunks outbound messages into frame-size-safe writes', () async {
    await transport.connect();
    radio.emitPeers(
      const <BleRadioPeer>[
        BleRadioPeer(id: 'peer-a', displayName: 'Peer A'),
      ],
    );
    final message = _message('hello over BLE ' * 30);

    await transport.send(message);

    expect(radio.sentFrames, isNotEmpty);
    expect(
      radio.sentFrames.every((frame) => frame.length <= 64),
      isTrue,
    );

    final received = await _reassembleSentFrames(radio.sentFrames);
    expect(received.id, message.id);
    expect(utf8.decode(received.payload), utf8.decode(message.payload));
  });

  test('reassembles out-of-order inbound BLE frames', () async {
    await transport.connect();
    final message = _message('incoming mesh payload ' * 20);
    radio.emitPeers(
      const <BleRadioPeer>[
        BleRadioPeer(id: 'peer-b', displayName: 'Peer B'),
      ],
    );

    await transport.send(message);
    final incoming = transport.incomingMessages.first;
    for (final frame in radio.sentFrames.reversed) {
      radio.emitFrame(frame);
    }

    final received = await incoming;
    expect(received.id, message.id);
    expect(utf8.decode(received.payload), utf8.decode(message.payload));
  });

  test('drops malformed inbound frames', () async {
    await transport.connect();
    final received = <MessageEnvelope>[];
    final subscription = transport.incomingMessages.listen(received.add);

    radio.emitFrame(Uint8List.fromList(<int>[1, 2, 3]));
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await subscription.cancel();
  });

  test('requires a connected peer before sending', () async {
    await transport.connect();

    await expectLater(
      transport.send(_message('queued')),
      throwsA(isA<StateError>()),
    );
  });

  test('maps radio peers to chat transport peers', () async {
    await transport.connect();
    final peersFuture = transport.nearbyPeers.first;

    radio.emitPeers(
      const <BleRadioPeer>[
        BleRadioPeer(id: 'peer-c', displayName: 'Trail Phone'),
      ],
    );

    final peers = await peersFuture;
    expect(peers.single.id, 'peer-c');
    expect(peers.single.displayName, 'Trail Phone');
  });

  test('starts and stops the underlying radio idempotently', () async {
    await transport.connect();
    await transport.connect();
    expect(radio.startCalls, 1);

    await transport.disconnect();
    await transport.disconnect();
    expect(radio.stopCalls, 1);
  });
}

Future<MessageEnvelope> _reassembleSentFrames(
  List<Uint8List> frames,
) async {
  final radio = FakeBleMeshRadio(maximumFrameBytes: 64);
  final transport = BleTransport(radio: radio);
  await transport.connect();
  final receivedFuture = transport.incomingMessages.first;
  for (final frame in frames) {
    radio.emitFrame(frame);
  }
  final received = await receivedFuture;
  await transport.disconnect();
  await radio.dispose();
  return received;
}

MessageEnvelope _message(String body) {
  return MessageEnvelope(
    id: '550e8400-e29b-41d4-a716-446655440000',
    senderId: 'sender-a',
    roomId: 'trail-room',
    timestampUtc: DateTime.utc(2026, 8, 4),
    hopLimit: 4,
    payload: Uint8List.fromList(utf8.encode(body)),
  );
}

class FakeBleMeshRadio implements BleMeshRadio {
  FakeBleMeshRadio({required this.maximumFrameBytes});

  final StreamController<BleRadioAvailability> _availabilityController =
      StreamController<BleRadioAvailability>.broadcast();
  final StreamController<Uint8List> _frameController =
      StreamController<Uint8List>.broadcast();
  final StreamController<List<BleRadioPeer>> _peerController =
      StreamController<List<BleRadioPeer>>.broadcast();

  BleRadioAvailability currentAvailability = BleRadioAvailability.ready;
  final List<Uint8List> sentFrames = <Uint8List>[];
  int startCalls = 0;
  int stopCalls = 0;

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
  final int maximumFrameBytes;

  @override
  Future<void> sendFrame(Uint8List frame) async {
    sentFrames.add(Uint8List.fromList(frame));
  }

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  void emitFrame(Uint8List frame) {
    _frameController.add(Uint8List.fromList(frame));
  }

  void emitPeers(List<BleRadioPeer> peers) {
    _peerController.add(List<BleRadioPeer>.unmodifiable(peers));
  }

  Future<void> dispose() async {
    await _availabilityController.close();
    await _frameController.close();
    await _peerController.close();
  }
}
