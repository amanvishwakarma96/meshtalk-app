import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/security/device_agreement_identity_store.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

void main() {
  test('creates and reloads one stable X25519 identity', () async {
    final values = _MemorySecureValueStore();
    final store = DeviceAgreementIdentityStore(
      values: values,
      nowUtc: () => DateTime.utc(2026, 8, 7),
    );

    final first = await store.loadOrCreate('device-a');
    final second = await store.loadOrCreate('device-a');

    expect(second.keyId, first.keyId);
    expect(second.publicKeyBytes, first.publicKeyBytes);
    expect(second.privateKeyBytes, first.privateKeyBytes);
  });

  test('fails closed when the stored X25519 key pair is modified', () async {
    final values = _MemorySecureValueStore();
    final store = DeviceAgreementIdentityStore(values: values);
    await store.loadOrCreate('device-a');

    final raw = jsonDecode(
      values.values['meshtalk.device-agreement-identity.v1']!,
    ) as Map<String, dynamic>;
    final privateKey = base64Url.decode(raw['privateKey'] as String);
    privateKey[0] ^= 0x01;
    raw['privateKey'] = base64UrlEncode(privateKey).replaceAll('=', '');
    values.values['meshtalk.device-agreement-identity.v1'] = jsonEncode(raw);

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

  test('does not reuse an agreement identity for another profile', () async {
    final values = _MemorySecureValueStore();
    final store = DeviceAgreementIdentityStore(values: values);
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
}

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
