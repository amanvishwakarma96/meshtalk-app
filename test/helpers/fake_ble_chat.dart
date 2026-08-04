import 'dart:async';
import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';

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
