import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_codec.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/transport/android_nearby_transport.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/nearby_connections_gateway.dart';
import 'package:meshtalk_app/core/transport/nearby_endpoint_identity.dart';

void main() {
  const localProfile = LocalProfile(
    deviceId: '11111111-1111-1111-1111-111111111111',
    displayName: 'Local Phone',
  );
  const identityCodec = NearbyEndpointIdentityCodec();
  const messageCodec = MessageCodec();

  late FakeNearbyConnectionsGateway gateway;
  late AndroidNearbyTransport transport;

  setUp(() {
    gateway = FakeNearbyConnectionsGateway();
    transport = AndroidNearbyTransport(
      profile: localProfile,
      gateway: gateway,
    );
  });

  tearDown(() async {
    await transport.disconnect();
  });

  test('maps denied Android Nearby permissions to an activation failure',
      () async {
    gateway.authorization = NearbyAuthorizationState.permissionDenied;

    await expectLater(
      transport.connect(),
      throwsA(
        isA<TransportActivationException>()
            .having(
              (error) => error.failure,
              'failure',
              TransportActivationFailure.permissionDenied,
            )
            .having(
              (error) => error.kind,
              'kind',
              TransportKind.localWifi,
            ),
      ),
    );

    expect(gateway.startAdvertisingCalls, 0);
    expect(gateway.startDiscoveryCalls, 0);
  });

  test('starts cluster advertising and discovery', () async {
    await transport.connect();

    expect(gateway.startAdvertisingCalls, 1);
    expect(gateway.startDiscoveryCalls, 1);
    expect(gateway.advertisedServiceId, transport.serviceId);
    expect(gateway.discoveredServiceId, transport.serviceId);
    expect(gateway.advertisedEndpointName, startsWith('MT1|'));
  });

  test('uses stable device ordering to avoid duplicate connection requests',
      () async {
    await transport.connect();
    final higherIdentity = identityCodec.encode(
      deviceId: '22222222-2222-2222-2222-222222222222',
      displayName: 'Higher Peer',
    );
    final lowerIdentity = identityCodec.encode(
      deviceId: '00000000-0000-0000-0000-000000000000',
      displayName: 'Lower Peer',
    );

    gateway.emitEndpointFound('endpoint-higher', higherIdentity);
    gateway.emitEndpointFound('endpoint-lower', lowerIdentity);
    await _drainEvents();

    expect(gateway.requestedEndpointIds, <String>['endpoint-higher']);
  });

  test('rejects malformed peers before accepting payload callbacks', () async {
    await transport.connect();

    gateway.emitConnectionInitiated(
      'bad-endpoint',
      const NearbyConnectionInfo(
        endpointName: 'not-a-meshtalk-peer',
        authenticationToken: 'token',
        isIncomingConnection: true,
      ),
    );
    await _drainEvents();

    expect(gateway.rejectedEndpointIds, contains('bad-endpoint'));
    expect(gateway.acceptedEndpointIds, isNot(contains('bad-endpoint')));
  });

  test('publishes connected peers and decodes incoming byte envelopes',
      () async {
    await transport.connect();
    final remoteIdentity = identityCodec.encode(
      deviceId: '22222222-2222-2222-2222-222222222222',
      displayName: 'Remote Phone',
    );
    final peerFuture = transport.nearbyPeers.firstWhere(
      (peers) => peers.isNotEmpty,
    );
    final incomingFuture = transport.incomingMessages.first;

    gateway.emitConnectionInitiated(
      'endpoint-a',
      NearbyConnectionInfo(
        endpointName: remoteIdentity,
        authenticationToken: 'token',
        isIncomingConnection: true,
      ),
    );
    await _drainEvents();
    gateway.emitConnectionResult(
      'endpoint-a',
      NearbyConnectionResult.connected,
    );

    final peers = await peerFuture;
    expect(peers.single.id, '22222222-2222-2222-2222-222222222222');
    expect(peers.single.displayName, 'Remote Phone');

    final message = _message('incoming', payloadLength: 4);
    gateway.emitBytes(
      'endpoint-a',
      messageCodec.encode(message),
    );

    expect((await incomingFuture).id, message.id);
  });

  test('broadcasts to connected peers and tolerates one failed endpoint',
      () async {
    await transport.connect();
    await _connectPeer(
      gateway,
      identityCodec,
      endpointId: 'endpoint-a',
      deviceId: '22222222-2222-2222-2222-222222222222',
    );
    await _connectPeer(
      gateway,
      identityCodec,
      endpointId: 'endpoint-b',
      deviceId: '33333333-3333-3333-3333-333333333333',
    );
    gateway.failedSendEndpointIds.add('endpoint-b');

    await transport.send(_message('broadcast', payloadLength: 16));

    expect(gateway.sentPayloads.keys, contains('endpoint-a'));
    expect(gateway.sentPayloads.keys, contains('endpoint-b'));
    expect(gateway.disconnectedEndpointIds, contains('endpoint-b'));
  });

  test('throws when no connected endpoint accepts a send', () async {
    await transport.connect();
    await _connectPeer(
      gateway,
      identityCodec,
      endpointId: 'endpoint-a',
      deviceId: '22222222-2222-2222-2222-222222222222',
    );
    gateway.failedSendEndpointIds.add('endpoint-a');

    await expectLater(
      transport.send(_message('failed', payloadLength: 16)),
      throwsStateError,
    );
  });

  test('rejects encoded messages above the conservative byte limit', () async {
    await transport.connect();
    await _connectPeer(
      gateway,
      identityCodec,
      endpointId: 'endpoint-a',
      deviceId: '22222222-2222-2222-2222-222222222222',
    );

    await expectLater(
      transport.send(
        _message(
          'oversized',
          payloadLength: AndroidNearbyTransport.maximumPayloadBytes,
        ),
      ),
      throwsStateError,
    );
  });

  test('stops discovery, advertising, and endpoints on disconnect', () async {
    await transport.connect();

    await transport.disconnect();

    expect(gateway.stopDiscoveryCalls, 1);
    expect(gateway.stopAdvertisingCalls, 1);
    expect(gateway.stopAllEndpointsCalls, 1);
  });
}

Future<void> _connectPeer(
  FakeNearbyConnectionsGateway gateway,
  NearbyEndpointIdentityCodec codec, {
  required String endpointId,
  required String deviceId,
}) async {
  gateway.emitConnectionInitiated(
    endpointId,
    NearbyConnectionInfo(
      endpointName: codec.encode(
        deviceId: deviceId,
        displayName: 'Peer $endpointId',
      ),
      authenticationToken: 'token',
      isIncomingConnection: true,
    ),
  );
  await _drainEvents();
  gateway.emitConnectionResult(
    endpointId,
    NearbyConnectionResult.connected,
  );
  await _drainEvents();
}

MessageEnvelope _message(String id, {required int payloadLength}) {
  return MessageEnvelope(
    id: id,
    senderId: '11111111-1111-1111-1111-111111111111',
    roomId: 'nearby',
    timestampUtc: DateTime.utc(2026, 8, 4),
    hopLimit: 4,
    payload: Uint8List.fromList(
      List<int>.generate(payloadLength, (index) => index % 256),
    ),
  );
}

Future<void> _drainEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class FakeNearbyConnectionsGateway implements NearbyConnectionsGateway {
  NearbyAuthorizationState authorization = NearbyAuthorizationState.authorized;
  bool advertisingResult = true;
  bool discoveryResult = true;
  bool requestResult = true;
  bool acceptResult = true;

  int startAdvertisingCalls = 0;
  int startDiscoveryCalls = 0;
  int stopAdvertisingCalls = 0;
  int stopDiscoveryCalls = 0;
  int stopAllEndpointsCalls = 0;
  String? advertisedEndpointName;
  String? advertisedServiceId;
  String? discoveredServiceId;

  final List<String> requestedEndpointIds = <String>[];
  final List<String> acceptedEndpointIds = <String>[];
  final List<String> rejectedEndpointIds = <String>[];
  final List<String> disconnectedEndpointIds = <String>[];
  final Set<String> failedSendEndpointIds = <String>{};
  final Map<String, List<Uint8List>> sentPayloads = <String, List<Uint8List>>{};
  final Map<String, NearbyBytesReceived> _bytesCallbacks =
      <String, NearbyBytesReceived>{};

  NearbyConnectionInitiated? _onConnectionInitiated;
  NearbyConnectionResultCallback? _onConnectionResult;
  NearbyDisconnected? _onDisconnected;
  NearbyEndpointFound? _onEndpointFound;
  NearbyEndpointLost? _onEndpointLost;

  @override
  bool get isSupported => true;

  @override
  Future<NearbyAuthorizationState> authorize() async => authorization;

  @override
  Future<bool> startAdvertising({
    required String endpointName,
    required String serviceId,
    required NearbyConnectionInitiated onConnectionInitiated,
    required NearbyConnectionResultCallback onConnectionResult,
    required NearbyDisconnected onDisconnected,
  }) async {
    startAdvertisingCalls += 1;
    advertisedEndpointName = endpointName;
    advertisedServiceId = serviceId;
    _onConnectionInitiated = onConnectionInitiated;
    _onConnectionResult = onConnectionResult;
    _onDisconnected = onDisconnected;
    return advertisingResult;
  }

  @override
  Future<bool> startDiscovery({
    required String endpointName,
    required String serviceId,
    required NearbyEndpointFound onEndpointFound,
    required NearbyEndpointLost onEndpointLost,
  }) async {
    startDiscoveryCalls += 1;
    discoveredServiceId = serviceId;
    _onEndpointFound = onEndpointFound;
    _onEndpointLost = onEndpointLost;
    return discoveryResult;
  }

  @override
  Future<bool> requestConnection({
    required String endpointName,
    required String endpointId,
    required NearbyConnectionInitiated onConnectionInitiated,
    required NearbyConnectionResultCallback onConnectionResult,
    required NearbyDisconnected onDisconnected,
  }) async {
    requestedEndpointIds.add(endpointId);
    _onConnectionInitiated = onConnectionInitiated;
    _onConnectionResult = onConnectionResult;
    _onDisconnected = onDisconnected;
    return requestResult;
  }

  @override
  Future<bool> acceptConnection({
    required String endpointId,
    required NearbyBytesReceived onBytesReceived,
  }) async {
    acceptedEndpointIds.add(endpointId);
    _bytesCallbacks[endpointId] = onBytesReceived;
    return acceptResult;
  }

  @override
  Future<bool> rejectConnection(String endpointId) async {
    rejectedEndpointIds.add(endpointId);
    return true;
  }

  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) async {
    sentPayloads.putIfAbsent(endpointId, () => <Uint8List>[]).add(bytes);
    if (failedSendEndpointIds.contains(endpointId)) {
      throw StateError('Endpoint send failed');
    }
  }

  @override
  Future<void> disconnectFromEndpoint(String endpointId) async {
    disconnectedEndpointIds.add(endpointId);
  }

  @override
  Future<void> stopAdvertising() async {
    stopAdvertisingCalls += 1;
  }

  @override
  Future<void> stopDiscovery() async {
    stopDiscoveryCalls += 1;
  }

  @override
  Future<void> stopAllEndpoints() async {
    stopAllEndpointsCalls += 1;
  }

  void emitEndpointFound(String endpointId, String endpointName) {
    _onEndpointFound?.call(
      endpointId,
      endpointName,
      'com.amanvishwakarma.meshtalk.nearby',
    );
  }

  void emitEndpointLost(String endpointId) {
    _onEndpointLost?.call(endpointId);
  }

  void emitConnectionInitiated(
    String endpointId,
    NearbyConnectionInfo info,
  ) {
    _onConnectionInitiated?.call(endpointId, info);
  }

  void emitConnectionResult(
    String endpointId,
    NearbyConnectionResult result,
  ) {
    _onConnectionResult?.call(endpointId, result);
  }

  void emitDisconnected(String endpointId) {
    _onDisconnected?.call(endpointId);
  }

  void emitBytes(String endpointId, Uint8List bytes) {
    _bytesCallbacks[endpointId]?.call(endpointId, bytes);
  }
}
