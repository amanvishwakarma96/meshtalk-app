import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:meshtalk_app/core/transport/nearby_connections_gateway.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

class PluginNearbyConnectionsGateway implements NearbyConnectionsGateway {
  PluginNearbyConnectionsGateway({
    Nearby? nearby,
    DeviceInfoPlugin? deviceInfo,
  })  : _nearby = nearby ?? Nearby(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final Nearby _nearby;
  final DeviceInfoPlugin _deviceInfo;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<NearbyAuthorizationState> authorize() async {
    if (!isSupported) {
      return NearbyAuthorizationState.unsupported;
    }

    try {
      final sdkInt = (await _deviceInfo.androidInfo).version.sdkInt;
      final permissions = <Permission>[];

      if (sdkInt <= 31) {
        permissions.add(Permission.location);
      }
      if (sdkInt >= 31) {
        permissions.addAll(<Permission>[
          Permission.bluetoothAdvertise,
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
        ]);
      }
      if (sdkInt >= 33) {
        permissions.add(Permission.nearbyWifiDevices);
      }

      final statuses = await permissions.request();
      final granted = statuses.values.every(
        (status) => status.isGranted || status.isLimited,
      );
      return granted
          ? NearbyAuthorizationState.authorized
          : NearbyAuthorizationState.permissionDenied;
    } catch (_) {
      return NearbyAuthorizationState.unavailable;
    }
  }

  @override
  Future<bool> startAdvertising({
    required String endpointName,
    required String serviceId,
    required NearbyConnectionInitiated onConnectionInitiated,
    required NearbyConnectionResultCallback onConnectionResult,
    required NearbyDisconnected onDisconnected,
  }) {
    return _nearby.startAdvertising(
      endpointName,
      Strategy.P2P_CLUSTER,
      serviceId: serviceId,
      onConnectionInitiated: (endpointId, info) {
        onConnectionInitiated(
          endpointId,
          NearbyConnectionInfo(
            endpointName: info.endpointName,
            authenticationToken: info.authenticationToken,
            isIncomingConnection: info.isIncomingConnection,
          ),
        );
      },
      onConnectionResult: (endpointId, status) {
        onConnectionResult(endpointId, _connectionResult(status));
      },
      onDisconnected: onDisconnected,
    );
  }

  @override
  Future<bool> startDiscovery({
    required String endpointName,
    required String serviceId,
    required NearbyEndpointFound onEndpointFound,
    required NearbyEndpointLost onEndpointLost,
  }) {
    return _nearby.startDiscovery(
      endpointName,
      Strategy.P2P_CLUSTER,
      serviceId: serviceId,
      onEndpointFound: onEndpointFound,
      onEndpointLost: onEndpointLost,
    );
  }

  @override
  Future<bool> requestConnection({
    required String endpointName,
    required String endpointId,
    required NearbyConnectionInitiated onConnectionInitiated,
    required NearbyConnectionResultCallback onConnectionResult,
    required NearbyDisconnected onDisconnected,
  }) {
    return _nearby.requestConnection(
      endpointName,
      endpointId,
      onConnectionInitiated: (id, info) {
        onConnectionInitiated(
          id,
          NearbyConnectionInfo(
            endpointName: info.endpointName,
            authenticationToken: info.authenticationToken,
            isIncomingConnection: info.isIncomingConnection,
          ),
        );
      },
      onConnectionResult: (id, status) {
        onConnectionResult(id, _connectionResult(status));
      },
      onDisconnected: onDisconnected,
    );
  }

  @override
  Future<bool> acceptConnection({
    required String endpointId,
    required NearbyBytesReceived onBytesReceived,
  }) {
    return _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (id, payload) {
        final bytes = payload.bytes;
        if (payload.type == PayloadType.BYTES && bytes != null) {
          onBytesReceived(id, Uint8List.fromList(bytes));
        }
      },
    );
  }

  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) {
    return _nearby.sendBytesPayload(endpointId, bytes);
  }

  @override
  Future<void> disconnectFromEndpoint(String endpointId) {
    return _nearby.disconnectFromEndpoint(endpointId);
  }

  @override
  Future<void> stopAdvertising() => _nearby.stopAdvertising();

  @override
  Future<void> stopDiscovery() => _nearby.stopDiscovery();

  @override
  Future<void> stopAllEndpoints() => _nearby.stopAllEndpoints();

  NearbyConnectionResult _connectionResult(Status status) {
    return switch (status) {
      Status.CONNECTED => NearbyConnectionResult.connected,
      Status.REJECTED => NearbyConnectionResult.rejected,
      Status.ERROR => NearbyConnectionResult.error,
    };
  }
}
