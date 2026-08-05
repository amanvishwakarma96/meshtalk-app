import 'dart:async';
import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/message_codec.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/ios_multipeer_gateway.dart';
import 'package:meshtalk_app/core/transport/nearby_endpoint_identity.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/core/transport/transport_runtime_diagnostics.dart';

class IosMultipeerTransport
    implements
        ChatTransport,
        PeerVerificationTransport,
        TransportRuntimeDiagnostics {
  IosMultipeerTransport({
    required LocalProfile profile,
    required IosMultipeerGateway gateway,
    MessageCodec codec = const MessageCodec(),
    NearbyEndpointIdentityCodec identityCodec =
        const NearbyEndpointIdentityCodec(),
  })  : _profile = profile,
        _gateway = gateway,
        _codec = codec,
        _identityCodec = identityCodec;

  static const int maximumPayloadBytes = 32 * 1024;

  final LocalProfile _profile;
  final IosMultipeerGateway _gateway;
  final MessageCodec _codec;
  final NearbyEndpointIdentityCodec _identityCodec;

  final StreamController<MessageEnvelope> _incomingMessages =
      StreamController<MessageEnvelope>.broadcast();
  final StreamController<List<NearbyPeer>> _nearbyPeers =
      StreamController<List<NearbyPeer>>.broadcast();
  final StreamController<List<PeerVerificationRequest>>
      _verificationRequests =
      StreamController<List<PeerVerificationRequest>>.broadcast();
  final StreamController<TransportRuntimeError> _runtimeErrors =
      StreamController<TransportRuntimeError>.broadcast();

  final Map<String, NearbyPeer> _knownPeers = <String, NearbyPeer>{};
  final Set<String> _connectedEndpointIds = <String>{};
  final Map<String, PeerVerificationRequest> _pendingVerifications =
      <String, PeerVerificationRequest>{};

  StreamSubscription<IosMultipeerEvent>? _eventSubscription;
  bool _started = false;
  bool _stoppingAfterFatalError = false;

  @override
  String get id => 'ios-multipeer';

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
  Stream<List<PeerVerificationRequest>> get verificationRequests =>
      _verificationRequests.stream;

  @override
  Stream<TransportRuntimeError> get runtimeErrors => _runtimeErrors.stream;

  @override
  List<PeerVerificationRequest> get currentVerificationRequests {
    final requests = _pendingVerifications.values.toList(growable: false)
      ..sort((left, right) => left.peerId.compareTo(right.peerId));
    return List<PeerVerificationRequest>.unmodifiable(requests);
  }

  @override
  Future<bool> isAvailable() async => _gateway.isSupported;

  @override
  Future<void> connect() async {
    if (_started) {
      return;
    }
    if (!_gateway.isSupported) {
      throw const TransportActivationException(
        transportId: 'ios-multipeer',
        kind: TransportKind.localWifi,
        failure: TransportActivationFailure.unsupported,
        message: 'iOS Multipeer Connectivity is not supported here.',
      );
    }

    await _eventSubscription?.cancel();
    _eventSubscription = _gateway.events.listen(_handleEvent);
    try {
      await _gateway.start(
        deviceId: _profile.deviceId,
        displayName: _identityCodec.sanitizeDisplayName(
          _profile.displayName,
        ),
      );
      _started = true;
    } catch (error) {
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      throw TransportActivationException(
        transportId: id,
        kind: kind,
        failure: TransportActivationFailure.unavailable,
        message:
            'iOS local-network discovery could not start. Check Local Network permission and try again.',
        cause: error,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_started &&
        _eventSubscription == null &&
        _knownPeers.isEmpty &&
        _pendingVerifications.isEmpty) {
      return;
    }

    _started = false;
    try {
      await _gateway.stop();
    } finally {
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      _knownPeers.clear();
      _connectedEndpointIds.clear();
      _pendingVerifications.clear();
      _publishPeers();
      _publishVerificationRequests();
    }
  }

  @override
  Future<void> approvePeer(String endpointId) async {
    if (!_pendingVerifications.containsKey(endpointId)) {
      throw StateError('The iOS peer verification request is stale.');
    }
    await _gateway.approvePeer(endpointId);
  }

  @override
  Future<void> rejectPeer(String endpointId) async {
    if (!_pendingVerifications.containsKey(endpointId)) {
      return;
    }
    await _gateway.rejectPeer(endpointId);
  }

  @override
  Future<void> send(MessageEnvelope message) async {
    if (!_started) {
      throw StateError('iOS Multipeer transport is not connected.');
    }
    if (_connectedEndpointIds.isEmpty) {
      throw StateError('No verified iOS Multipeer peers are connected.');
    }

    final payload = _codec.encode(message);
    if (payload.length > maximumPayloadBytes) {
      throw StateError(
        'Encoded message is ${payload.length} bytes; the iOS Multipeer '
        'fallback limit is $maximumPayloadBytes bytes.',
      );
    }

    var successfulDeliveries = 0;
    Object? lastError;
    final failedEndpoints = <String>[];
    for (final endpointId in _connectedEndpointIds.toList(growable: false)) {
      try {
        await _gateway.sendBytes(
          endpointId: endpointId,
          bytes: Uint8List.fromList(payload),
        );
        successfulDeliveries += 1;
      } catch (error) {
        lastError = error;
        failedEndpoints.add(endpointId);
      }
    }

    for (final endpointId in failedEndpoints) {
      _connectedEndpointIds.remove(endpointId);
      _knownPeers.remove(endpointId);
    }
    if (failedEndpoints.isNotEmpty) {
      _publishPeers();
    }
    if (successfulDeliveries == 0) {
      throw StateError(
        'iOS Multipeer could not deliver the message to any peer: '
        '${lastError ?? 'unknown transport error'}',
      );
    }
  }

  void _handleEvent(IosMultipeerEvent event) {
    switch (event.type) {
      case IosMultipeerEventType.started:
        _started = true;
      case IosMultipeerEventType.stopped:
        _started = false;
      case IosMultipeerEventType.verificationRequested:
        _handleVerificationRequested(event);
      case IosMultipeerEventType.verificationRemoved:
        final endpointId = event.endpointId;
        if (endpointId != null &&
            _pendingVerifications.remove(endpointId) != null) {
          _publishVerificationRequests();
        }
      case IosMultipeerEventType.peerConnected:
        _handlePeerConnected(event);
      case IosMultipeerEventType.peerDisconnected:
        _handlePeerDisconnected(event.endpointId);
      case IosMultipeerEventType.bytesReceived:
        _handleBytesReceived(event);
      case IosMultipeerEventType.error:
        _handleRuntimeError(event);
    }
  }

  void _handleVerificationRequested(IosMultipeerEvent event) {
    final endpointId = event.endpointId;
    final peerId = event.peerId;
    final token = event.authenticationToken;
    if (endpointId == null ||
        peerId == null ||
        endpointId == _profile.deviceId ||
        token == null ||
        !RegExp(r'^\d{6}$').hasMatch(token)) {
      return;
    }

    final displayName = _identityCodec.sanitizeDisplayName(
      event.displayName ?? 'MeshTalk',
    );
    _knownPeers[endpointId] = NearbyPeer(
      id: peerId,
      displayName: displayName,
    );
    _pendingVerifications[endpointId] = PeerVerificationRequest(
      transportId: id,
      endpointId: endpointId,
      peerId: peerId,
      displayName: displayName,
      authenticationToken: token,
      isIncomingConnection: event.isIncomingConnection ?? false,
    );
    _publishVerificationRequests();
  }

  void _handlePeerConnected(IosMultipeerEvent event) {
    final endpointId = event.endpointId;
    final peerId = event.peerId;
    if (endpointId == null ||
        peerId == null ||
        endpointId == _profile.deviceId) {
      return;
    }

    _knownPeers[endpointId] = NearbyPeer(
      id: peerId,
      displayName: _identityCodec.sanitizeDisplayName(
        event.displayName ?? _knownPeers[endpointId]?.displayName ?? 'MeshTalk',
      ),
    );
    _connectedEndpointIds.add(endpointId);
    _pendingVerifications.remove(endpointId);
    _publishVerificationRequests();
    _publishPeers();
  }

  void _handlePeerDisconnected(String? endpointId) {
    if (endpointId == null) {
      return;
    }
    _connectedEndpointIds.remove(endpointId);
    _pendingVerifications.remove(endpointId);
    _knownPeers.remove(endpointId);
    _publishVerificationRequests();
    _publishPeers();
  }

  void _handleBytesReceived(IosMultipeerEvent event) {
    final endpointId = event.endpointId;
    final bytes = event.bytes;
    if (endpointId == null ||
        bytes == null ||
        !_connectedEndpointIds.contains(endpointId)) {
      return;
    }
    try {
      _incomingMessages.add(_codec.decode(bytes));
    } on FormatException {
      // Native byte payloads remain untrusted after transport verification.
    }
  }

  void _handleRuntimeError(IosMultipeerEvent event) {
    final message = event.message ?? 'Unknown iOS Multipeer error.';
    _runtimeErrors.add(
      TransportRuntimeError(transportId: id, message: message),
    );

    final endpointId = event.endpointId;
    if (endpointId != null) {
      _connectedEndpointIds.remove(endpointId);
      _pendingVerifications.remove(endpointId);
      _knownPeers.remove(endpointId);
      _publishVerificationRequests();
      _publishPeers();
      return;
    }

    if (!_stoppingAfterFatalError) {
      _stoppingAfterFatalError = true;
      _started = false;
      unawaited(_stopAfterFatalError());
    }
  }

  Future<void> _stopAfterFatalError() async {
    try {
      await _gateway.stop();
    } catch (_) {
      // The runtime error is already visible through diagnostics.
    } finally {
      _stoppingAfterFatalError = false;
      _connectedEndpointIds.clear();
      _pendingVerifications.clear();
      _knownPeers.clear();
      _publishVerificationRequests();
      _publishPeers();
    }
  }

  void _publishPeers() {
    final peers = _connectedEndpointIds
        .map((endpointId) => _knownPeers[endpointId])
        .whereType<NearbyPeer>()
        .toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    _nearbyPeers.add(List<NearbyPeer>.unmodifiable(peers));
  }

  void _publishVerificationRequests() {
    _verificationRequests.add(currentVerificationRequests);
  }
}
