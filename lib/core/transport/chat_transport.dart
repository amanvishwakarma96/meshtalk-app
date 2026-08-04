import 'package:meshtalk_app/core/ble/message_envelope.dart';

enum TransportKind {
  bleMesh,
  localWifi,
  internetRelay,
}

enum TransportActivationFailure {
  permissionDenied,
  unsupported,
  unavailable,
}

class TransportActivationException implements Exception {
  const TransportActivationException({
    required this.transportId,
    required this.kind,
    required this.failure,
    required this.message,
    this.cause,
  });

  final String transportId;
  final TransportKind kind;
  final TransportActivationFailure failure;
  final String message;
  final Object? cause;

  @override
  String toString() =>
      'TransportActivationException($transportId, $failure, $message)';
}

class NearbyPeer {
  const NearbyPeer({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

class TransportCapabilities {
  const TransportCapabilities({
    required this.supportsRelay,
    required this.isOffline,
    this.maxPayloadBytes,
  });

  final bool supportsRelay;
  final bool isOffline;
  final int? maxPayloadBytes;
}

abstract interface class ChatTransport {
  String get id;
  TransportKind get kind;
  TransportCapabilities get capabilities;
  Stream<MessageEnvelope> get incomingMessages;
  Stream<List<NearbyPeer>> get nearbyPeers;

  Future<bool> isAvailable();
  Future<void> connect();
  Future<void> disconnect();
  Future<void> send(MessageEnvelope message);
}
