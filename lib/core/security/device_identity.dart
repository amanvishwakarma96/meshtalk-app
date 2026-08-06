import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class DeviceIdentity {
  DeviceIdentity({
    required this.deviceId,
    required Uint8List publicKeyBytes,
    required Uint8List privateKeyBytes,
    required this.createdAtUtc,
  })  : publicKeyBytes = Uint8List.fromList(publicKeyBytes),
        privateKeyBytes = Uint8List.fromList(privateKeyBytes) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Invalid device ID.');
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
        'Ed25519 private seeds must contain exactly 32 bytes.',
      );
    }
  }

  final String deviceId;
  final Uint8List publicKeyBytes;
  final Uint8List privateKeyBytes;
  final DateTime createdAtUtc;

  SimplePublicKey get publicKey => SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );

  SimpleKeyPairData get keyPair => SimpleKeyPairData(
        privateKeyBytes,
        publicKey: publicKey,
        type: KeyPairType.ed25519,
      );

  Future<String> fingerprint({HashAlgorithm? hashAlgorithm}) async {
    final digest = await (hashAlgorithm ?? Sha256()).hash(publicKeyBytes);
    final text = base64UrlEncode(digest.bytes.take(10).toList())
        .replaceAll('=', '')
        .toUpperCase();
    return '${text.substring(0, 5)}-${text.substring(5, 10)}';
  }
}
