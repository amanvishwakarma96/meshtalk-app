import 'dart:typed_data';

class DeviceIdentity {
  DeviceIdentity({
    required this.deviceId,
    required this.keyId,
    required Uint8List publicKeyBytes,
    required Uint8List privateKeyBytes,
    required this.createdAtUtc,
  })  : publicKeyBytes = Uint8List.fromList(publicKeyBytes),
        privateKeyBytes = Uint8List.fromList(privateKeyBytes) {
    if (deviceId.trim().isEmpty) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Must not be empty.');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{8,24}$').hasMatch(keyId)) {
      throw ArgumentError.value(keyId, 'keyId', 'Invalid identity key ID.');
    }
    if (this.publicKeyBytes.length != 32) {
      throw ArgumentError.value(
        this.publicKeyBytes.length,
        'publicKeyBytes',
        'Ed25519 public keys must contain exactly 32 bytes.',
      );
    }
    if (this.privateKeyBytes.length != 32) {
      throw ArgumentError.value(
        this.privateKeyBytes.length,
        'privateKeyBytes',
        'Ed25519 private keys must contain exactly 32 bytes.',
      );
    }
  }

  final String deviceId;
  final String keyId;
  final Uint8List publicKeyBytes;
  final Uint8List privateKeyBytes;
  final DateTime createdAtUtc;

  DeviceIdentitySummary get summary => DeviceIdentitySummary(
        deviceId: deviceId,
        keyId: keyId,
        createdAtUtc: createdAtUtc,
      );
}

class DeviceIdentitySummary {
  const DeviceIdentitySummary({
    required this.deviceId,
    required this.keyId,
    required this.createdAtUtc,
  });

  final String deviceId;
  final String keyId;
  final DateTime createdAtUtc;

  String get fingerprint => identityFingerprint(keyId);
}

String identityFingerprint(String keyId) {
  final normalized = keyId.toUpperCase();
  if (normalized.length <= 8) {
    return normalized;
  }
  return '${normalized.substring(0, 4)}-${normalized.substring(4, 8)}';
}
