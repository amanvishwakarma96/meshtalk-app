import 'dart:typed_data';

enum IosMultipeerEventType {
  started,
  stopped,
  verificationRequested,
  verificationRemoved,
  peerConnected,
  peerDisconnected,
  bytesReceived,
  error,
}

class IosMultipeerEvent {
  const IosMultipeerEvent({
    required this.type,
    this.endpointId,
    this.peerId,
    this.displayName,
    this.authenticationToken,
    this.isIncomingConnection,
    this.bytes,
    this.message,
  });

  final IosMultipeerEventType type;
  final String? endpointId;
  final String? peerId;
  final String? displayName;
  final String? authenticationToken;
  final bool? isIncomingConnection;
  final Uint8List? bytes;
  final String? message;
}

abstract interface class IosMultipeerGateway {
  bool get isSupported;
  Stream<IosMultipeerEvent> get events;

  Future<void> start({
    required String deviceId,
    required String displayName,
  });

  Future<void> stop();
  Future<void> approvePeer(String endpointId);
  Future<void> rejectPeer(String endpointId);

  Future<void> sendBytes({
    required String endpointId,
    required Uint8List bytes,
  });
}
