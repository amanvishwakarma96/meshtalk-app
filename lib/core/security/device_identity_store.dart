import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

class DeviceIdentityStore {
  DeviceIdentityStore({
    required SecureValueStore values,
    Ed25519? algorithm,
    HashAlgorithm? hashAlgorithm,
    DateTime Function()? nowUtc,
  })  : _values = values,
        _algorithm = algorithm ?? Ed25519(),
        _hashAlgorithm = hashAlgorithm ?? Sha256(),
        _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static const String _storageKey = 'meshtalk.device-identity.v1';

  final SecureValueStore _values;
  final Ed25519 _algorithm;
  final HashAlgorithm _hashAlgorithm;
  final DateTime Function() _nowUtc;

  Future<DeviceIdentity> loadOrCreate(String deviceId) async {
    final encoded = await _values.read(_storageKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return _create(deviceId);
    }
    return _decode(encoded, expectedDeviceId: deviceId);
  }

  Future<DeviceIdentity> _create(String deviceId) async {
    final keyPair = await _algorithm.newKeyPair();
    final extracted = await keyPair.extract();
    final publicKey = extracted.publicKey.bytes;
    final identity = DeviceIdentity(
      deviceId: deviceId,
      keyId: await deriveKeyId(publicKey),
      publicKeyBytes: Uint8List.fromList(publicKey),
      privateKeyBytes: Uint8List.fromList(extracted.bytes),
      createdAtUtc: _nowUtc(),
    );
    await _write(identity);
    extracted.destroy();
    return identity;
  }

  Future<String> deriveKeyId(List<int> publicKeyBytes) async {
    if (publicKeyBytes.length != 32) {
      throw ArgumentError.value(
        publicKeyBytes.length,
        'publicKeyBytes',
        'Ed25519 public keys must contain exactly 32 bytes.',
      );
    }
    final digest = await _hashAlgorithm.hash(publicKeyBytes);
    return _base64UrlWithoutPadding(digest.bytes.take(8).toList());
  }

  DeviceIdentity _decode(String encoded, {required String expectedDeviceId}) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('Unsupported device identity version.');
      }
      final deviceId = decoded['deviceId'];
      final keyId = decoded['keyId'];
      final publicKey = decoded['publicKey'];
      final privateKey = decoded['privateKey'];
      final createdAtUtc = decoded['createdAtUtc'];
      if (deviceId is! String ||
          keyId is! String ||
          publicKey is! String ||
          privateKey is! String ||
          createdAtUtc is! String) {
        throw const FormatException('Device identity fields are malformed.');
      }
      if (deviceId != expectedDeviceId) {
        throw const FormatException(
          'Stored signing identity belongs to a different device ID.',
        );
      }
      return DeviceIdentity(
        deviceId: deviceId,
        keyId: keyId,
        publicKeyBytes: Uint8List.fromList(_decodeBase64Url(publicKey)),
        privateKeyBytes: Uint8List.fromList(_decodeBase64Url(privateKey)),
        createdAtUtc: DateTime.parse(createdAtUtc).toUtc(),
      );
    } on FormatException catch (error) {
      throw StateError('Device signing identity is corrupt: ${error.message}');
    } on Object catch (error) {
      throw StateError('Device signing identity is corrupt: $error');
    }
  }

  Future<void> _write(DeviceIdentity identity) async {
    await _values.write(
      _storageKey,
      jsonEncode(<String, Object>{
        'version': 1,
        'deviceId': identity.deviceId,
        'keyId': identity.keyId,
        'publicKey': _base64UrlWithoutPadding(identity.publicKeyBytes),
        'privateKey': _base64UrlWithoutPadding(identity.privateKeyBytes),
        'createdAtUtc': identity.createdAtUtc.toUtc().toIso8601String(),
      }),
    );
  }

  String _base64UrlWithoutPadding(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  List<int> _decodeBase64Url(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    return base64Url.decode('$value$padding');
  }
}
