import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/security/device_identity_store.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

void main() {
  test('creates and reloads one stable Ed25519 identity', () async {
    final values = _MemorySecureValueStore();
    final firstStore = DeviceIdentityStore(
      values: values,
      nowUtc: () => DateTime.utc(2026, 8, 6),
    );

    final first = await firstStore.loadOrCreate('device-a');
    final second =
        await DeviceIdentityStore(values: values).loadOrCreate('device-a');

    expect(second.deviceId, first.deviceId);
    expect(second.keyId, first.keyId);
    expect(second.publicKeyBytes, first.publicKeyBytes);
    expect(second.privateKeyBytes, first.privateKeyBytes);
    expect(first.publicKeyBytes.length, 32);
    expect(first.privateKeyBytes.length, 32);
  });

  test('does not load an identity for a different device ID', () async {
    final values = _MemorySecureValueStore();
    final store = DeviceIdentityStore(values: values);
    await store.loadOrCreate('device-a');

    await expectLater(
      store.loadOrCreate('device-b'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('different device ID'),
        ),
      ),
    );
  });

  test('fails closed when secure identity storage is corrupt', () async {
    final values = _MemorySecureValueStore();
    await values.write(
      'meshtalk.device-identity.v1',
      jsonEncode(<String, Object>{
        'version': 1,
        'deviceId': 'device-a',
        'keyId': 'brokenKey90_',
        'publicKey': 'AA',
        'privateKey': 'AA',
        'createdAtUtc': DateTime.utc(2026, 8, 6).toIso8601String(),
      }),
    );

    await expectLater(
      DeviceIdentityStore(values: values).loadOrCreate('device-a'),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a stored fingerprint that does not match the public key',
      () async {
    final values = _MemorySecureValueStore();
    final store = DeviceIdentityStore(values: values);
    await store.loadOrCreate('device-a');
    final state = values.decodeIdentity()..['keyId'] = 'wrongKey90_';
    await values.writeIdentity(state);

    await expectLater(
      store.loadOrCreate('device-a'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('fingerprint does not match'),
        ),
      ),
    );
  });

  test('rejects a private key that does not match the stored public key',
      () async {
    final values = _MemorySecureValueStore();
    final otherValues = _MemorySecureValueStore();
    final store = DeviceIdentityStore(values: values);
    await store.loadOrCreate('device-a');
    await DeviceIdentityStore(values: otherValues).loadOrCreate('device-b');
    final state = values.decodeIdentity()
      ..['privateKey'] = otherValues.decodeIdentity()['privateKey'];
    await values.writeIdentity(state);

    await expectLater(
      store.loadOrCreate('device-a'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('private key does not match'),
        ),
      ),
    );
  });
}

class _MemorySecureValueStore implements SecureValueStore {
  static const String identityKey = 'meshtalk.device-identity.v1';

  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  Map<String, dynamic> decodeIdentity() {
    return jsonDecode(_values[identityKey]!) as Map<String, dynamic>;
  }

  Future<void> writeIdentity(Map<String, dynamic> value) {
    return write(identityKey, jsonEncode(value));
  }
}
