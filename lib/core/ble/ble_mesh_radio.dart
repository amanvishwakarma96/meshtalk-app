import 'dart:typed_data';

enum BleRadioAvailability {
  unsupported,
  unauthorized,
  poweredOff,
  ready,
}

class BleRadioPeer {
  const BleRadioPeer({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}

abstract interface class BleMeshRadio {
  BleRadioAvailability get availability;
  Stream<BleRadioAvailability> get availabilityChanges;
  Stream<Uint8List> get incomingFrames;
  Stream<List<BleRadioPeer>> get connectedPeers;
  int get maximumFrameBytes;

  Future<void> start();
  Future<void> stop();
  Future<void> sendFrame(Uint8List frame);
}
