class PeerVerificationRequest {
  const PeerVerificationRequest({
    required this.transportId,
    required this.endpointId,
    required this.peerId,
    required this.displayName,
    required this.authenticationToken,
    required this.isIncomingConnection,
  });

  final String transportId;
  final String endpointId;
  final String peerId;
  final String displayName;
  final String authenticationToken;
  final bool isIncomingConnection;
}

abstract interface class PeerVerificationTransport {
  List<PeerVerificationRequest> get currentVerificationRequests;
  Stream<List<PeerVerificationRequest>> get verificationRequests;

  Future<void> approvePeer(String endpointId);
  Future<void> rejectPeer(String endpointId);
}
