import 'dart:io';
import 'dart:typed_data';

import 'package:meshtalk_app/core/transport/ios_multipeer_gateway.dart';
import 'package:meshtalk_multipeer/meshtalk_multipeer.dart';

class PluginIosMultipeerGateway implements IosMultipeerGateway {
  PluginIosMultipeerGateway({MeshTalkMultipeer? plugin})
      : _plugin = plugin ?? MeshTalkMultipeer();

  final MeshTalkMultipeer _plugin;
  Stream<IosMultipeerEvent>? _events;

  @override
  bool get isSupported => Platform.isIOS;

  @override
  Stream<IosMultipeerEvent> get events {
    return _events ??= _plugin.events.map(_mapEvent).asBroadcastStream();
  }

  @override
  Future<void> start({
    required String deviceId,
    required String displayName,
  }) async {
    if (!isSupported || !await _plugin.isSupported()) {
      throw UnsupportedError('iOS Multipeer Connectivity is unavailable.');
    }
    await _plugin.start(deviceId: deviceId, displayName: displayName);
  }

  @override
  Future<void> stop() => _plugin.stop();

  @override
  Future<void> approvePeer(String endpointId) {
    return _plugin.approvePeer(endpointId);
  }

  @override
  Future<void> rejectPeer(String endpointId) {
    return _plugin.rejectPeer(endpointId);
  }

  @override
  Future<void> sendBytes({
    required String endpointId,
    required Uint8List bytes,
  }) {
    return _plugin.sendBytes(endpointId: endpointId, bytes: bytes);
  }

  IosMultipeerEvent _mapEvent(MeshTalkMultipeerEvent event) {
    return IosMultipeerEvent(
      type: IosMultipeerEventType.values.byName(event.type.name),
      endpointId: event.endpointId,
      peerId: event.peerId,
      displayName: event.displayName,
      authenticationToken: event.authenticationToken,
      isIncomingConnection: event.isIncomingConnection,
      bytes: event.bytes,
      message: event.message,
    );
  }
}
