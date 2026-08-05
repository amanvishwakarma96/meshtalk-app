import 'dart:async';
import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';

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

  void emitAvailability(BleRadioAvailability availability) {
    currentAvailability = availability;
    _availabilityController.add(availability);
  }

  Future<void> close() async {
    await _availabilityController.close();
    await _frameController.close();
    await _peerController.close();
  }
}

class FakeChatTransport implements ChatTransport {
  FakeChatTransport(
    this.radio, {
    this.transportId = 'fake-ble',
    this.transportKind = TransportKind.bleMesh,
    this.forcedAvailability,
  });

  final FakeBleRadio radio;
  final String transportId;
  final TransportKind transportKind;
  bool? forcedAvailability;
  final StreamController<MessageEnvelope> _incomingController =
      StreamController<MessageEnvelope>.broadcast();
  final StreamController<List<NearbyPeer>> _peerController =
      StreamController<List<NearbyPeer>>.broadcast();
  final List<MessageEnvelope> sentMessages = <MessageEnvelope>[];
  List<NearbyPeer> _peers = const <NearbyPeer>[];
  bool _connected = false;
  int availabilityChecks = 0;

  bool get connected => _connected;

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        supportsRelay: true,
        isOffline: true,
        maxPayloadBytes: 64,
      );

  @override
  String get id => transportId;

  @override
  Stream<MessageEnvelope> get incomingMessages => _incomingController.stream;

  @override
  TransportKind get kind => transportKind;

  @override
  Stream<List<NearbyPeer>> get nearbyPeers => _peerController.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    if (transportKind == TransportKind.bleMesh) {
      await radio.start();
    }
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _peers = const <NearbyPeer>[];
    _peerController.add(const <NearbyPeer>[]);
  }

  @override
  Future<bool> isAvailable() async {
    availabilityChecks += 1;
    final forced = forcedAvailability;
    if (forced != null) {
      return forced;
    }
    return transportKind == TransportKind.bleMesh
        ? radio.availability == BleRadioAvailability.ready
        : true;
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

class FakeVerifiableChatTransport extends FakeChatTransport
    implements PeerVerificationTransport {
  FakeVerifiableChatTransport(
    super.radio, {
    super.transportId = 'fake-android-nearby',
    super.transportKind = TransportKind.localWifi,
    super.forcedAvailability,
  });

  final StreamController<List<PeerVerificationRequest>>
      _verificationController =
      StreamController<List<PeerVerificationRequest>>.broadcast();
  final List<PeerVerificationRequest> _verificationRequests =
      <PeerVerificationRequest>[];
  final List<String> approvedEndpointIds = <String>[];
  final List<String> rejectedEndpointIds = <String>[];

  @override
  List<PeerVerificationRequest> get currentVerificationRequests =>
      List<PeerVerificationRequest>.unmodifiable(_verificationRequests);

  @override
  Stream<List<PeerVerificationRequest>> get verificationRequests =>
      _verificationController.stream;

  @override
  Future<void> approvePeer(String endpointId) async {
    final removed = _removeVerification(endpointId);
    if (!removed) {
      throw StateError('Verification request missing');
    }
    approvedEndpointIds.add(endpointId);
    _publishVerifications();
  }

  @override
  Future<void> rejectPeer(String endpointId) async {
    final removed = _removeVerification(endpointId);
    if (!removed) {
      return;
    }
    rejectedEndpointIds.add(endpointId);
    _publishVerifications();
  }

  void emitVerification(PeerVerificationRequest request) {
    _verificationRequests
      ..removeWhere(
        (existing) =>
            existing.transportId == request.transportId &&
            existing.endpointId == request.endpointId,
      )
      ..add(request);
    _publishVerifications();
  }

  @override
  Future<void> disconnect() async {
    await super.disconnect();
    if (_verificationRequests.isNotEmpty) {
      _verificationRequests.clear();
      _publishVerifications();
    }
  }

  @override
  Future<void> close() async {
    await super.close();
    await _verificationController.close();
  }

  bool _removeVerification(String endpointId) {
    final before = _verificationRequests.length;
    _verificationRequests.removeWhere(
      (request) => request.endpointId == endpointId,
    );
    return _verificationRequests.length != before;
  }

  void _publishVerifications() {
    _verificationController.add(currentVerificationRequests);
  }
}
