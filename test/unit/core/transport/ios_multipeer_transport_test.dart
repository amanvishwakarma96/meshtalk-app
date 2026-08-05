import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_codec.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/ios_multipeer_gateway.dart';
import 'package:meshtalk_app/core/transport/ios_multipeer_transport.dart';
import 'package:meshtalk_app/core/transport/transport_runtime_diagnostics.dart';

void main() {
  const profile = LocalProfile(
    deviceId: '11111111-1111-1111-1111-111111111111',
    displayName: 'Local iPhone',
  );
  const codec = MessageCodec();

  late FakeIosMultipeerGateway gateway;
  late IosMultipeerTransport transport;

  setUp(() {
    gateway = FakeIosMultipeerGateway();
    transport = IosMultipeerTransport(
      profile: profile,
      gateway: gateway,
    );
  });

  tearDown(() async {
    await transport.disconnect();
    await gateway.close();
  });

  test('maps an unsupported Apple platform to activation failure', () async {
    gateway.supported = false;

    await expectLater(
      transport.connect(),
      throwsA(
        isA<TransportActivationException>()
            .having(
              (error) => error.failure,
              'failure',
              TransportActivationFailure.unsupported,
            )
            .having(
              (error) => error.kind,
              'kind',
              TransportKind.localWifi,
            ),
      ),
    );

    expect(gateway.startCalls, 0);
  });

  test('starts the gateway with the stable local profile', () async {
    await transport.connect();

    expect(gateway.startCalls, 1);
    expect(gateway.startedDeviceId, profile.deviceId);
    expect(gateway.startedDisplayName, 'Local iPhone');
  });

  test('publishes verification and delegates approval', () async {
    await transport.connect();
    final requestsFuture = transport.verificationRequests.firstWhere(
      (requests) => requests.isNotEmpty,
    );

    gateway.emit(
      const IosMultipeerEvent(
        type: IosMultipeerEventType.verificationRequested,
        endpointId: '22222222-2222-2222-2222-222222222222',
        peerId: '22222222-2222-2222-2222-222222222222',
        displayName: 'Remote iPhone',
        authenticationToken: '143902',
        isIncomingConnection: true,
      ),
    );

    final request = (await requestsFuture).single;
    expect(request.displayName, 'Remote iPhone');
    expect(request.authenticationToken, '143902');
    expect(request.isIncomingConnection, isTrue);

    await transport.approvePeer(request.endpointId);
    expect(gateway.approvedEndpointIds, <String>[request.endpointId]);
  });

  test('ignores malformed verification events', () async {
    await transport.connect();

    gateway.emit(
      const IosMultipeerEvent(
        type: IosMultipeerEventType.verificationRequested,
        endpointId: 'bad-peer',
        peerId: 'bad-peer',
        displayName: 'Bad Peer',
        authenticationToken: 'not-six-digits',
      ),
    );
    await _drainEvents();

    expect(transport.currentVerificationRequests, isEmpty);
  });

  test('publishes verified peers and decodes incoming envelopes', () async {
    await transport.connect();
    final peersFuture = transport.nearbyPeers.firstWhere(
      (peers) => peers.isNotEmpty,
    );
    final incomingFuture = transport.incomingMessages.first;
    const endpointId = '22222222-2222-2222-2222-222222222222';

    gateway.emit(
      const IosMultipeerEvent(
        type: IosMultipeerEventType.peerConnected,
        endpointId: endpointId,
        peerId: endpointId,
        displayName: 'Remote iPhone',
      ),
    );

    final peers = await peersFuture;
    expect(peers.single.id, endpointId);
    expect(peers.single.displayName, 'Remote iPhone');

    final message = _message('incoming', payloadLength: 8);
    gateway.emit(
      IosMultipeerEvent(
        type: IosMultipeerEventType.bytesReceived,
        endpointId: endpointId,
        peerId: endpointId,
        bytes: codec.encode(message),
      ),
    );

    expect((await incomingFuture).id, message.id);
  });

  test('broadcasts to verified peers and tolerates one failed send', () async {
    await transport.connect();
    const first = '22222222-2222-2222-2222-222222222222';
    const second = '33333333-3333-3333-3333-333333333333';
    gateway
      ..emit(_connected(first, 'First iPhone'))
      ..emit(_connected(second, 'Second iPhone'))
      ..failedSendEndpointIds.add(second);
    await _drainEvents();

    await transport.send(_message('broadcast', payloadLength: 16));

    expect(gateway.sentPayloads.keys, containsAll(<String>[first, second]));
  });

  test('throws when no verified peer accepts a payload', () async {
    await transport.connect();
    const endpointId = '22222222-2222-2222-2222-222222222222';
    gateway
      ..emit(_connected(endpointId, 'Remote iPhone'))
      ..failedSendEndpointIds.add(endpointId);
    await _drainEvents();

    await expectLater(
      transport.send(_message('failed', payloadLength: 16)),
      throwsStateError,
    );
  });

  test('rejects an encoded message above the conservative limit', () async {
    await transport.connect();
    const endpointId = '22222222-2222-2222-2222-222222222222';
    gateway.emit(_connected(endpointId, 'Remote iPhone'));
    await _drainEvents();

    await expectLater(
      transport.send(
        _message(
          'oversized',
          payloadLength: IosMultipeerTransport.maximumPayloadBytes,
        ),
      ),
      throwsStateError,
    );
  });

  test('surfaces fatal native errors and stops the gateway', () async {
    await transport.connect();
    final errorFuture = transport.runtimeErrors.first;

    gateway.emit(
      const IosMultipeerEvent(
        type: IosMultipeerEventType.error,
        message: 'Local network permission denied.',
      ),
    );

    final TransportRuntimeError error = await errorFuture;
    expect(error.transportId, transport.id);
    expect(error.message, contains('permission denied'));
    await _drainEvents();
    expect(gateway.stopCalls, 1);
  });

  test('stops the native gateway and clears peers', () async {
    await transport.connect();
    gateway.emit(
      _connected(
        '22222222-2222-2222-2222-222222222222',
        'Remote iPhone',
      ),
    );
    await _drainEvents();

    await transport.disconnect();

    expect(gateway.stopCalls, 1);
    expect(transport.currentVerificationRequests, isEmpty);
  });
}

IosMultipeerEvent _connected(String endpointId, String displayName) {
  return IosMultipeerEvent(
    type: IosMultipeerEventType.peerConnected,
    endpointId: endpointId,
    peerId: endpointId,
    displayName: displayName,
  );
}

MessageEnvelope _message(String id, {required int payloadLength}) {
  return MessageEnvelope(
    id: id,
    senderId: '11111111-1111-1111-1111-111111111111',
    roomId: 'nearby',
    timestampUtc: DateTime.utc(2026, 8, 5),
    hopLimit: 4,
    payload: Uint8List.fromList(
      List<int>.generate(payloadLength, (index) => index % 256),
    ),
  );
}

Future<void> _drainEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class FakeIosMultipeerGateway implements IosMultipeerGateway {
  final StreamController<IosMultipeerEvent> _events =
      StreamController<IosMultipeerEvent>.broadcast();

  bool supported = true;
  int startCalls = 0;
  int stopCalls = 0;
  String? startedDeviceId;
  String? startedDisplayName;
  final List<String> approvedEndpointIds = <String>[];
  final List<String> rejectedEndpointIds = <String>[];
  final Set<String> failedSendEndpointIds = <String>{};
  final Map<String, List<Uint8List>> sentPayloads = <String, List<Uint8List>>{};

  @override
  bool get isSupported => supported;

  @override
  Stream<IosMultipeerEvent> get events => _events.stream;

  @override
  Future<void> start({
    required String deviceId,
    required String displayName,
  }) async {
    startCalls += 1;
    startedDeviceId = deviceId;
    startedDisplayName = displayName;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> approvePeer(String endpointId) async {
    approvedEndpointIds.add(endpointId);
  }

  @override
  Future<void> rejectPeer(String endpointId) async {
    rejectedEndpointIds.add(endpointId);
  }

  @override
  Future<void> sendBytes({
    required String endpointId,
    required Uint8List bytes,
  }) async {
    sentPayloads.putIfAbsent(endpointId, () => <Uint8List>[]).add(bytes);
    if (failedSendEndpointIds.contains(endpointId)) {
      throw StateError('Native send failed');
    }
  }

  void emit(IosMultipeerEvent event) {
    _events.add(event);
  }

  Future<void> close() => _events.close();
}
