import 'dart:typed_data';

enum NearbyAuthorizationState {
  authorized,
  permissionDenied,
  unsupported,
  unavailable,
}

enum NearbyConnectionResult {
  connected,
  rejected,
  error,
}

class NearbyConnectionInfo {
  const NearbyConnectionInfo({
    required this.endpointName,
    required this.authenticationToken,
    required this.isIncomingConnection,
  });

  final String endpointName;
  final String authenticationToken;
  final bool isIncomingConnection;
}

typedef NearbyConnectionInitiated = void Function(
  String endpointId,
  NearbyConnectionInfo connectionInfo,
);
typedef NearbyConnectionResultCallback = void Function(
  String endpointId,
  NearbyConnectionResult result,
);
typedef NearbyDisconnected = void Function(String endpointId);
typedef NearbyEndpointFound = void Function(
  String endpointId,
  String endpointName,
  String serviceId,
);
typedef NearbyEndpointLost = void Function(String? endpointId);
typedef NearbyBytesReceived = void Function(
  String endpointId,
  Uint8List bytes,
);

abstract interface class NearbyConnectionsGateway {
  bool get isSupported;

  Future<NearbyAuthorizationState> authorize();

  Future<bool> startAdvertising({
    required String endpointName,
    required String serviceId,
    required NearbyConnectionInitiated onConnectionInitiated,
    required NearbyConnectionResultCallback onConnectionResult,
    required NearbyDisconnected onDisconnected,
  });

  Future<bool> startDiscovery({
    required String endpointName,
    required String serviceId,
    required NearbyEndpointFound onEndpointFound,
    required NearbyEndpointLost onEndpointLost,
  });

  Future<bool> requestConnection({
    required String endpointName,
    required String endpointId,
    required NearbyConnectionInitiated onConnectionInitiated,
    required NearbyConnectionResultCallback onConnectionResult,
    required NearbyDisconnected onDisconnected,
  });

  Future<bool> acceptConnection({
    required String endpointId,
    required NearbyBytesReceived onBytesReceived,
  });

  Future<void> sendBytes(String endpointId, Uint8List bytes);
  Future<void> disconnectFromEndpoint(String endpointId);
  Future<void> stopAdvertising();
  Future<void> stopDiscovery();
  Future<void> stopAllEndpoints();
}
