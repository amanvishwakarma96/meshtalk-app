import 'dart:typed_data';

import 'package:meshtalk_app/core/security/device_identity.dart';

class DeviceAgreementIdentity {
  DeviceAgreementIdentity({
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
      throw ArgumentError.value(keyId, 'keyId', 'Invalid agreement key ID.');
    }
    if (this.publicKeyBytes.length != 32) {
      throw ArgumentError.value(
        this.publicKeyBytes.length,
        'publicKeyBytes',
        'X25519 public keys must contain exactly 32 bytes.',
      );
    }
    if (this.privateKeyBytes.length != 32) {
      throw ArgumentError.value(
        this.privateKeyBytes.length,
        'privateKeyBytes',
        'X25519 private keys must contain exactly 32 bytes.',
      );
    }
  }

  final String deviceId;
  final String keyId;
  final Uint8List publicKeyBytes;
  final Uint8List privateKeyBytes;
  final DateTime createdAtUtc;

  DeviceAgreementIdentitySummary get summary => DeviceAgreementIdentitySummary(
        deviceId: deviceId,
        keyId: keyId,
        createdAtUtc: createdAtUtc,
      );
}

class DeviceAgreementIdentitySummary {
  const DeviceAgreementIdentitySummary({
    required this.deviceId,
    required this.keyId,
    required this.createdAtUtc,
  });

  final String deviceId;
  final String keyId;
  final DateTime createdAtUtc;

  String get fingerprint => identityFingerprint(keyId);
}
