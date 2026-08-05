import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

enum MeshTalkMultipeerEventType {
  started,
  stopped,
  verificationRequested,
  verificationRemoved,
  peerConnected,
  peerDisconnected,
  bytesReceived,
  error,
}

class MeshTalkMultipeerEvent {
  const MeshTalkMultipeerEvent({
    required this.type,
    this.endpointId,
    this.peerId,
    this.displayName,
    this.authenticationToken,
    this.isIncomingConnection,
    this.bytes,
    this.message,
  });

  factory MeshTalkMultipeerEvent.fromMap(Map<Object?, Object?> map) {
    final rawType = map['type'];
    final type = MeshTalkMultipeerEventType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () => MeshTalkMultipeerEventType.error,
    );
    final rawBytes = map['bytes'];
    return MeshTalkMultipeerEvent(
      type: type,
      endpointId: map['endpointId'] as String?,
      peerId: map['peerId'] as String?,
      displayName: map['displayName'] as String?,
      authenticationToken: map['authenticationToken'] as String?,
      isIncomingConnection: map['isIncomingConnection'] as bool?,
      bytes: rawBytes is Uint8List
          ? rawBytes
          : rawBytes is List<int>
              ? Uint8List.fromList(rawBytes)
              : null,
      message: map['message'] as String?,
    );
  }

  final MeshTalkMultipeerEventType type;
  final String? endpointId;
  final String? peerId;
  final String? displayName;
  final String? authenticationToken;
  final bool? isIncomingConnection;
  final Uint8List? bytes;
  final String? message;
}

class MeshTalkMultipeer {
  MeshTalkMultipeer({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel =
            methodChannel ?? const MethodChannel('meshtalk.multipeer/methods'),
        _eventChannel =
            eventChannel ?? const EventChannel('meshtalk.multipeer/events');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<MeshTalkMultipeerEvent>? _events;

  Stream<MeshTalkMultipeerEvent> get events {
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map(
          (event) => MeshTalkMultipeerEvent.fromMap(
            Map<Object?, Object?>.from(event as Map),
          ),
        )
        .asBroadcastStream();
  }

  Future<bool> isSupported() async {
    return await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
  }

  Future<void> start({
    required String deviceId,
    required String displayName,
  }) async {
    await _methodChannel.invokeMethod<void>(
      'start',
      <String, Object>{
        'deviceId': deviceId,
        'displayName': displayName,
      },
    );
  }

  Future<void> stop() async {
    await _methodChannel.invokeMethod<void>('stop');
  }

  Future<void> approvePeer(String endpointId) async {
    await _methodChannel.invokeMethod<void>(
      'approvePeer',
      <String, Object>{'endpointId': endpointId},
    );
  }

  Future<void> rejectPeer(String endpointId) async {
    await _methodChannel.invokeMethod<void>(
      'rejectPeer',
      <String, Object>{'endpointId': endpointId},
    );
  }

  Future<void> sendBytes({
    required String endpointId,
    required Uint8List bytes,
  }) async {
    await _methodChannel.invokeMethod<void>(
      'sendBytes',
      <String, Object>{
        'endpointId': endpointId,
        'bytes': bytes,
      },
    );
  }
}
