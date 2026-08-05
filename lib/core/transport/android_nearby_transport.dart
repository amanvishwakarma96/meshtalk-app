import 'dart:async';
import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/message_codec.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/nearby_connections_gateway.dart';
import 'package:meshtalk_app/core/transport/nearby_endpoint_identity.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';

class AndroidNearbyTransport
    implements ChatTransport, PeerVerificationTransport {
  AndroidNearbyTransport({
    required LocalProfile profile,
    required NearbyConnectionsGateway gateway,
    MessageCodec codec = const MessageCodec(),
    NearbyEndpointIdentityCodec identityCodec =
        const NearbyEndpointIdentityCodec(),
    this.serviceId = 'com.amanvishwakarma.meshtalk.nearby',
  })  : _profile = profile,
        _gateway = gateway,
        _codec = codec,
        _identityCodec = identityCodec {
    _endpointName = _identityCodec.encode(
      deviceId: _profile.deviceId,
      displayName: _profile.displayName,
    );
  }

  static const int maximumPayloadBytes = 32 * 1024;

  final LocalProfile _profile;
  final NearbyConnectionsGateway _gateway;
  final MessageCodec _codec;
  final NearbyEndpointIdentityCodec _identityCodec;
  final String serviceId;

  final StreamController<MessageEnvelope> _incomingMessages =
      StreamController<MessageEnvelope>.broadcast();
  final StreamController<List<NearbyPeer>> _nearbyPeers =
      StreamController<List<NearbyPeer>>.broadcast();
  final StreamController<List<PeerVerificationRequest>> _verificationRequests =
      StreamController<List<PeerVerificationRequest>>.broadcast();
  final Map<String, NearbyEndpointIdentity> _knownEndpoints =
      <String, NearbyEndpointIdentity>{};
  final Map<String, PeerVerificationRequest> _pendingVerifications =
      <String, PeerVerificationRequest>{};
  final Set<String> _connectedEndpointIds = <String>{};
  final Set<String> _pendingEndpointIds = <String>{};
  final Set<String> _acceptedEndpointIds = <String>{};

  late final String _endpointName;
  bool _started = false;

  @override
  String get id => 'android-nearby';

  @override
  TransportKind get kind => TransportKind.localWifi;

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        supportsRelay: true,
        isOffline: true,
        maxPayloadBytes: maximumPayloadBytes,
      );

  @override
  Stream<MessageEnvelope> get incomingMessages => _incomingMessages.stream;

  @override
  Stream<List<NearbyPeer>> get nearbyPeers => _nearbyPeers.stream;

  @override
  List<PeerVerificationRequest> get currentVerificationRequests {
    final requests = _pendingVerifications.values.toList(growable: false)
      ..sort((left, right) => left.peerId.compareTo(right.peerId));
    return List<PeerVerificationRequest>.unmodifiable(requests);
  }

  @override
  Stream<List<PeerVerificationRequest>> get verificationRequests =>
      _verificationRequests.stream;

  @override
  Future<bool> isAvailable() async => _gateway.isSupported;

  @override
  Future<void> connect() async {
    if (_started) {
      return;
    }

    final authorization = await _gateway.authorize();
    switch (authorization) {
      case NearbyAuthorizationState.authorized:
        break;
      case NearbyAuthorizationState.permissionDenied:
        throw const TransportActivationException(
          transportId: 'android-nearby',
          kind: TransportKind.localWifi,
          failure: TransportActivationFailure.permissionDenied,
          message: 'Nearby devices and local-network permissions are required.',
        );
      case NearbyAuthorizationState.unsupported:
        throw const TransportActivationException(
          transportId: 'android-nearby',
          kind: TransportKind.localWifi,
          failure: TransportActivationFailure.unsupported,
          message: 'Android Nearby Connections is not supported here.',
        );
      case NearbyAuthorizationState.unavailable:
        throw const TransportActivationException(
          transportId: 'android-nearby',
          kind: TransportKind.localWifi,
          failure: TransportActivationFailure.unavailable,
          message: 'Android Nearby Connections is temporarily unavailable.',
        );
    }

    _started = true;
    try {
      final advertising = await _gateway.startAdvertising(
        endpointName: _endpointName,
        serviceId: serviceId,
        onConnectionInitiated: _handleConnectionInitiated,
        onConnectionResult: _handleConnectionResult,
        onDisconnected: _handleDisconnected,
      );
      if (!advertising) {
        throw StateError('Nearby advertising could not start.');
      }

      final discovery = await _gateway.startDiscovery(
        endpointName: _endpointName,
        serviceId: serviceId,
        onEndpointFound: _handleEndpointFound,
        onEndpointLost: _handleEndpointLost,
      );
      if (!discovery) {
        throw StateError('Nearby discovery could not start.');
      }
    } catch (error) {
      _started = false;
      await _stopGatewayBestEffort();
      throw TransportActivationException(
        transportId: id,
        kind: kind,
        failure: TransportActivationFailure.unavailable,
        message: 'Android Nearby fallback could not start.',
        cause: error,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_started &&
        _knownEndpoints.isEmpty &&
        _connectedEndpointIds.isEmpty &&
        _pendingEndpointIds.isEmpty &&
        _acceptedEndpointIds.isEmpty &&
        _pendingVerifications.isEmpty) {
      return;
    }

    _started = false;
    await _stopGatewayBestEffort();
    _knownEndpoints.clear();
    _connectedEndpointIds.clear();
    _pendingEndpointIds.clear();
    _acceptedEndpointIds.clear();
    _pendingVerifications.clear();
    _publishPeers();
    _publishVerificationRequests();
  }

  @override
  Future<void> approvePeer(String endpointId) async {
    final request = _pendingVerifications[endpointId];
    if (!_started || request == null) {
      throw StateError(
          'The Nearby peer verification request is no longer active.');
    }
    if (!_acceptedEndpointIds.add(endpointId)) {
      return;
    }

    _pendingVerifications.remove(endpointId);
    _publishVerificationRequests();
    await _acceptConnection(endpointId);
  }

  @override
  Future<void> rejectPeer(String endpointId) async {
    final existed = _pendingVerifications.remove(endpointId) != null;
    _pendingEndpointIds.remove(endpointId);
    _acceptedEndpointIds.remove(endpointId);
    _connectedEndpointIds.remove(endpointId);
    _knownEndpoints.remove(endpointId);
    if (existed) {
      _publishVerificationRequests();
    }
    _publishPeers();
    await _rejectEndpointBestEffort(endpointId);
  }

  @override
  Future<void> send(MessageEnvelope message) async {
    if (!_started) {
      throw StateError('Android Nearby transport is not connected.');
    }
    if (_connectedEndpointIds.isEmpty) {
      throw StateError('No verified Android Nearby peers are connected.');
    }

    final payload = _codec.encode(message);
    if (payload.length > maximumPayloadBytes) {
      throw StateError(
        'Encoded message is ${payload.length} bytes; the Android Nearby '
        'fallback limit is $maximumPayloadBytes bytes.',
      );
    }

    var successfulDeliveries = 0;
    var peersChanged = false;
    final endpointIds = _connectedEndpointIds.toList(growable: false);
    Object? lastError;
    for (final endpointId in endpointIds) {
      try {
        await _gateway.sendBytes(endpointId, Uint8List.fromList(payload));
        successfulDeliveries += 1;
      } catch (error) {
        lastError = error;
        peersChanged = _connectedEndpointIds.remove(endpointId) || peersChanged;
        _knownEndpoints.remove(endpointId);
        _acceptedEndpointIds.remove(endpointId);
        unawaited(_disconnectEndpointBestEffort(endpointId));
      }
    }

    if (peersChanged) {
      _publishPeers();
    }
    if (successfulDeliveries == 0) {
      throw StateError(
        'Android Nearby could not deliver the message to any peer: '
        '${lastError ?? 'unknown transport error'}',
      );
    }
  }

  void _handleEndpointFound(
    String endpointId,
    String endpointName,
    String discoveredServiceId,
  ) {
    if (!_started || discoveredServiceId != serviceId) {
      return;
    }

    final identity = _identityCodec.decode(endpointName);
    if (!_isValidRemoteIdentity(identity)) {
      return;
    }

    _knownEndpoints[endpointId] = identity!;
    final shouldInitiate = _profile.deviceId.compareTo(identity.deviceId) < 0;
    if (!shouldInitiate ||
        _connectedEndpointIds.contains(endpointId) ||
        !_pendingEndpointIds.add(endpointId)) {
      return;
    }

    unawaited(_requestConnection(endpointId));
  }

  void _handleEndpointLost(String? endpointId) {
    if (endpointId == null || _connectedEndpointIds.contains(endpointId)) {
      return;
    }
    _pendingEndpointIds.remove(endpointId);
    _acceptedEndpointIds.remove(endpointId);
    final verificationRemoved =
        _pendingVerifications.remove(endpointId) != null;
    _knownEndpoints.remove(endpointId);
    if (verificationRemoved) {
      _publishVerificationRequests();
    }
  }

  void _handleConnectionInitiated(
    String endpointId,
    NearbyConnectionInfo connectionInfo,
  ) {
    if (!_started) {
      unawaited(_rejectEndpointBestEffort(endpointId));
      return;
    }

    final identity = _identityCodec.decode(connectionInfo.endpointName);
    final authenticationToken = connectionInfo.authenticationToken.trim();
    if (!_isValidRemoteIdentity(identity) || authenticationToken.isEmpty) {
      unawaited(_rejectEndpointBestEffort(endpointId));
      return;
    }
    if (_connectedEndpointIds.contains(endpointId) ||
        _acceptedEndpointIds.contains(endpointId) ||
        _pendingVerifications.containsKey(endpointId)) {
      return;
    }

    _knownEndpoints[endpointId] = identity!;
    _pendingEndpointIds.add(endpointId);
    _pendingVerifications[endpointId] = PeerVerificationRequest(
      transportId: id,
      endpointId: endpointId,
      peerId: identity.deviceId,
      displayName: identity.displayName,
      authenticationToken: authenticationToken,
      isIncomingConnection: connectionInfo.isIncomingConnection,
    );
    _publishVerificationRequests();
  }

  void _handleConnectionResult(
    String endpointId,
    NearbyConnectionResult result,
  ) {
    _pendingEndpointIds.remove(endpointId);
    final verificationRemoved =
        _pendingVerifications.remove(endpointId) != null;
    if (!_started ||
        result != NearbyConnectionResult.connected ||
        !_acceptedEndpointIds.contains(endpointId) ||
        !_knownEndpoints.containsKey(endpointId)) {
      _connectedEndpointIds.remove(endpointId);
      _acceptedEndpointIds.remove(endpointId);
      if (result != NearbyConnectionResult.connected) {
        _knownEndpoints.remove(endpointId);
      }
      if (verificationRemoved) {
        _publishVerificationRequests();
      }
      _publishPeers();
      return;
    }

    _connectedEndpointIds.add(endpointId);
    if (verificationRemoved) {
      _publishVerificationRequests();
    }
    _publishPeers();
  }

  void _handleDisconnected(String endpointId) {
    _pendingEndpointIds.remove(endpointId);
    _connectedEndpointIds.remove(endpointId);
    _acceptedEndpointIds.remove(endpointId);
    final verificationRemoved =
        _pendingVerifications.remove(endpointId) != null;
    _knownEndpoints.remove(endpointId);
    if (verificationRemoved) {
      _publishVerificationRequests();
    }
    _publishPeers();
  }

  Future<void> _requestConnection(String endpointId) async {
    try {
      final requested = await _gateway.requestConnection(
        endpointName: _endpointName,
        endpointId: endpointId,
        onConnectionInitiated: _handleConnectionInitiated,
        onConnectionResult: _handleConnectionResult,
        onDisconnected: _handleDisconnected,
      );
      if (!requested) {
        _pendingEndpointIds.remove(endpointId);
        _knownEndpoints.remove(endpointId);
      }
    } catch (_) {
      _pendingEndpointIds.remove(endpointId);
      _knownEndpoints.remove(endpointId);
    }
  }

  Future<void> _acceptConnection(String endpointId) async {
    try {
      final accepted = await _gateway.acceptConnection(
        endpointId: endpointId,
        onBytesReceived: _handleBytesReceived,
      );
      if (!accepted) {
        _pendingEndpointIds.remove(endpointId);
        _acceptedEndpointIds.remove(endpointId);
        _knownEndpoints.remove(endpointId);
        await _rejectEndpointBestEffort(endpointId);
      }
    } catch (_) {
      _pendingEndpointIds.remove(endpointId);
      _acceptedEndpointIds.remove(endpointId);
      _knownEndpoints.remove(endpointId);
      await _rejectEndpointBestEffort(endpointId);
      rethrow;
    }
  }

  void _handleBytesReceived(String endpointId, Uint8List bytes) {
    if (!_started ||
        !_connectedEndpointIds.contains(endpointId) ||
        !_acceptedEndpointIds.contains(endpointId)) {
      return;
    }
    try {
      _incomingMessages.add(_codec.decode(bytes));
    } on FormatException {
      // Nearby byte payloads are untrusted and malformed envelopes are dropped.
    }
  }

  bool _isValidRemoteIdentity(NearbyEndpointIdentity? identity) {
    return identity != null && identity.deviceId != _profile.deviceId;
  }

  void _publishPeers() {
    final peers = _connectedEndpointIds
        .map((endpointId) {
          final identity = _knownEndpoints[endpointId];
          if (identity == null) {
            return null;
          }
          return NearbyPeer(
            id: identity.deviceId,
            displayName: identity.displayName,
          );
        })
        .whereType<NearbyPeer>()
        .toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    _nearbyPeers.add(List<NearbyPeer>.unmodifiable(peers));
  }

  void _publishVerificationRequests() {
    _verificationRequests.add(currentVerificationRequests);
  }

  Future<void> _disconnectEndpointBestEffort(String endpointId) async {
    try {
      await _gateway.disconnectFromEndpoint(endpointId);
    } catch (_) {
      // Best-effort cleanup after a peer-specific send failure.
    }
  }

  Future<void> _rejectEndpointBestEffort(String endpointId) async {
    try {
      await _gateway.rejectConnection(endpointId);
    } catch (_) {
      // Invalid or declined endpoints remain disconnected even if rejection fails.
    }
  }

  Future<void> _stopGatewayBestEffort() async {
    try {
      await _gateway.stopDiscovery();
    } catch (_) {
      // Best-effort cleanup.
    }
    try {
      await _gateway.stopAdvertising();
    } catch (_) {
      // Best-effort cleanup.
    }
    try {
      await _gateway.stopAllEndpoints();
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
