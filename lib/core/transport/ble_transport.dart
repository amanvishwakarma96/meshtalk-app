import 'dart:async';
import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/ble_chunk_frame_codec.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/message_chunker.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/ble/message_reassembler.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';

class BleTransport implements ChatTransport {
  BleTransport({
    required BleMeshRadio radio,
    BleChunkFrameCodec frameCodec = const BleChunkFrameCodec(),
    MessageReassembler? reassembler,
  })  : _radio = radio,
        _frameCodec = frameCodec,
        _reassembler = reassembler ?? MessageReassembler();

  final BleMeshRadio _radio;
  final BleChunkFrameCodec _frameCodec;
  final MessageReassembler _reassembler;
  final StreamController<MessageEnvelope> _incomingMessages =
      StreamController<MessageEnvelope>.broadcast();
  final StreamController<List<NearbyPeer>> _nearbyPeers =
      StreamController<List<NearbyPeer>>.broadcast();

  StreamSubscription<Uint8List>? _frameSubscription;
  StreamSubscription<List<BleRadioPeer>>? _peerSubscription;
  List<BleRadioPeer> _latestPeers = const <BleRadioPeer>[];
  bool _connected = false;

  @override
  String get id => 'ble-mesh';

  @override
  TransportKind get kind => TransportKind.bleMesh;

  @override
  TransportCapabilities get capabilities => TransportCapabilities(
        supportsRelay: true,
        isOffline: true,
        maxPayloadBytes: _radio.maximumFrameBytes,
      );

  @override
  Stream<MessageEnvelope> get incomingMessages => _incomingMessages.stream;

  @override
  Stream<List<NearbyPeer>> get nearbyPeers => _nearbyPeers.stream;

  @override
  Future<bool> isAvailable() async {
    return _radio.availability == BleRadioAvailability.ready;
  }

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }

    _frameSubscription = _radio.incomingFrames.listen(_handleFrame);
    _peerSubscription = _radio.connectedPeers.listen(_handlePeers);
    try {
      await _radio.start();
      _connected = true;
    } catch (_) {
      await _frameSubscription?.cancel();
      await _peerSubscription?.cancel();
      _frameSubscription = null;
      _peerSubscription = null;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_connected &&
        _frameSubscription == null &&
        _peerSubscription == null) {
      return;
    }

    _connected = false;
    await _frameSubscription?.cancel();
    await _peerSubscription?.cancel();
    _frameSubscription = null;
    _peerSubscription = null;
    _latestPeers = const <BleRadioPeer>[];
    _nearbyPeers.add(const <NearbyPeer>[]);
    await _radio.stop();
  }

  @override
  Future<void> send(MessageEnvelope message) async {
    if (!_connected) {
      throw StateError('BLE transport is not connected.');
    }
    if (_latestPeers.isEmpty) {
      throw StateError('No BLE mesh peers are connected.');
    }

    final maximumFrameBytes = _radio.maximumFrameBytes;
    if (maximumFrameBytes <= BleChunkFrameCodec.headerBytes) {
      throw StateError(
        'BLE maximum frame size must exceed '
        '${BleChunkFrameCodec.headerBytes} bytes.',
      );
    }

    final chunker = MessageChunker(
      headerOverheadBytes: BleChunkFrameCodec.headerBytes,
    );
    final chunks = chunker.chunk(
      message,
      negotiatedMtu: maximumFrameBytes,
    );
    if (chunks.length > BleChunkFrameCodec.maximumChunks) {
      throw StateError(
        'Message requires ${chunks.length} BLE chunks; '
        'the protocol limit is ${BleChunkFrameCodec.maximumChunks}.',
      );
    }

    for (final chunk in chunks) {
      await _radio.sendFrame(_frameCodec.encode(chunk));
    }
  }

  void _handleFrame(Uint8List frame) {
    try {
      final chunk = _frameCodec.decode(frame);
      final envelope = _reassembler.add(chunk);
      if (envelope != null) {
        _incomingMessages.add(envelope);
      }
    } on FormatException {
      // Invalid radio frames are untrusted input and are intentionally dropped.
    }
  }

  void _handlePeers(List<BleRadioPeer> peers) {
    _latestPeers = List<BleRadioPeer>.unmodifiable(peers);
    _nearbyPeers.add(
      List<NearbyPeer>.unmodifiable(
        peers.map(
          (peer) => NearbyPeer(
            id: peer.id,
            displayName: peer.displayName,
          ),
        ),
      ),
    );
  }
}
