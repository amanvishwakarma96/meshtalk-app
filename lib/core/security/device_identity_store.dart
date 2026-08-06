import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

class DeviceIdentityStore {
  DeviceIdentityStore({
    required SecureValueStore values,
    Random? random,
    DateTime Function()? nowUtc,
    Ed25519? algorithm,
  })  : _values = values,
        _random = random ?? Random.secure(),
        _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
        _algorithm = algorithm ?? Ed25519();

  static const String _storageKey = 'meshtalk.device-identity.v1';

  final SecureValueStore _values;
  final Random _random;
  final DateTime Function() _nowUtc;
  final Ed25519 _algorithm;

  Future<DeviceIdentity> loadOrCreate(String deviceId) async {
    final encoded = await _values.read(_storageKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return _create(deviceId);
    }
    return _decode(encoded, expectedDeviceId: deviceId);
  }

  Future<DeviceIdentity> _create(String deviceId) async {
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    final keyPair = await _algorithm.newKeyPairFromSeed(seed);
    final keyData = await keyPair.extract();
    final identity = DeviceIdentity(
      deviceId: deviceId,
      publicKeyBytes: Uint8List.fromList(keyData.publicKey.bytes),
      privateKeyBytes: seed,
      createdAtUtc: _nowUtc(),
    );
    await _values.write(_storageKey, _encode(identity));
    return identity;
  }

  String _encode(DeviceIdentity identity) {
    return jsonEncode(<String, Object>{
      'version': 1,
      'deviceId': identity.deviceId,
      'publicKey': base64UrlEncode(identity.publicKeyBytes),
      'privateSeed': base64UrlEncode(identity.privateKeyBytes),
      'createdAtUtc': identity.createdAtUtc.toUtc().toIso8601String(),
    });
  }

  DeviceIdentity _decode(String encoded, {required String expectedDeviceId}) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('Unsupported device identity version.');
      }
      final deviceId = decoded['deviceId'];
      final publicKey = decoded['publicKey'];
      final privateSeed = decoded['privateSeed'];
      final createdAtUtc = decoded['createdAtUtc'];
      if (deviceId is! String ||
          publicKey is! String ||
          privateSeed is! String ||
          createdAtUtc is! String) {
        throw const FormatException('Device identity fields are malformed.');
      }
      if (deviceId != expectedDeviceId) {
        throw const FormatException(
          'Device identity does not match the local profile.',
        );
      }
      return DeviceIdentity(
        deviceId: deviceId,
        publicKeyBytes: Uint8List.fromList(base64Url.decode(publicKey)),
        privateKeyBytes: Uint8List.fromList(base64Url.decode(privateSeed)),
        createdAtUtc: DateTime.parse(createdAtUtc).toUtc(),
      );
    } on FormatException catch (error) {
      throw StateError('Device identity storage is corrupt: ${error.message}');
    } on Object catch (error) {
      throw StateError('Device identity storage is corrupt: $error');
    }
  }
}
