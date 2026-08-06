import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/security/device_identity_store.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

void main() {
  test('creates and reloads one stable Ed25519 identity', () async {
    final values = MemorySecureValueStore();
    final firstStore = DeviceIdentityStore(
      values: values,
      random: Random(7),
      nowUtc: () => DateTime.utc(2026, 8, 6),
    );

    final first = await firstStore.loadOrCreate('deviceIdentifier1234');
    final second = await DeviceIdentityStore(
      values: values,
      random: Random(99),
    ).loadOrCreate('deviceIdentifier1234');

    expect(second.deviceId, first.deviceId);
    expect(second.publicKeyBytes, first.publicKeyBytes);
    expect(second.privateKeyBytes, first.privateKeyBytes);
    expect(await second.fingerprint(), await first.fingerprint());
  });

  test('rejects identity data bound to another local profile', () async {
    final values = MemorySecureValueStore();
    await DeviceIdentityStore(
      values: values,
      random: Random(11),
    ).loadOrCreate('deviceIdentifier1234');

    expect(
      () => DeviceIdentityStore(values: values)
          .loadOrCreate('differentDeviceId1234'),
      throwsA(isA<StateError>()),
    );
  });

  test('fails closed when secure identity storage is corrupt', () async {
    final values = MemorySecureValueStore();
    await values.write('meshtalk.device-identity.v1', '{bad json');

    expect(
      () => DeviceIdentityStore(values: values)
          .loadOrCreate('deviceIdentifier1234'),
      throwsA(isA<StateError>()),
    );
  });
}

class MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
