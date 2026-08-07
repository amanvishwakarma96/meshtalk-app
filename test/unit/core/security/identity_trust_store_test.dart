import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/security/identity_trust_store.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

void main() {
  late _MemorySecureValueStore values;
  late IdentityTrustStore store;
  var minute = 0;

  setUp(() {
    values = _MemorySecureValueStore();
    minute = 0;
    store = IdentityTrustStore(
      values: values,
      nowUtc: () => DateTime.utc(2026, 8, 6, 8, minute++),
    );
  });

  test('pins the first key and recognizes it on later messages', () async {
    final publicKey = Uint8List.fromList(List<int>.filled(32, 1));

    final first = await store.evaluate(
      senderId: 'device-a',
      keyId: 'firstKey90_',
      publicKeyBytes: publicKey,
    );
    final second = await store.evaluate(
      senderId: 'device-a',
      keyId: 'firstKey90_',
      publicKeyBytes: publicKey,
    );

    expect(first.decision, IdentityTrustDecision.firstSeen);
    expect(second.decision, IdentityTrustDecision.trustedSeen);
    expect((await store.list()).single.keyId, 'firstKey90_');
  });

  test('marks a compared fingerprint verified', () async {
    final publicKey = Uint8List.fromList(List<int>.filled(32, 2));
    await store.evaluate(
      senderId: 'device-a',
      keyId: 'firstKey90_',
      publicKeyBytes: publicKey,
    );

    await store.markVerified('device-a', 'firstKey90_');
    final result = await store.evaluate(
      senderId: 'device-a',
      keyId: 'firstKey90_',
      publicKeyBytes: publicKey,
    );

    expect(result.decision, IdentityTrustDecision.trustedVerified);
    expect(result.identity.trustLevel, IdentityTrustLevel.verified);
  });

  test('stages a changed key without replacing the pinned key', () async {
    await store.evaluate(
      senderId: 'device-a',
      keyId: 'firstKey90_',
      publicKeyBytes: Uint8List.fromList(List<int>.filled(32, 3)),
    );

    final result = await store.evaluate(
      senderId: 'device-a',
      keyId: 'secondKey9_',
      publicKeyBytes: Uint8List.fromList(List<int>.filled(32, 4)),
    );

    expect(result.decision, IdentityTrustDecision.changed);
    expect(result.identity.keyId, 'firstKey90_');
    expect(result.identity.pendingKeyId, 'secondKey9_');
    expect(result.identity.hasPendingChange, isTrue);
  });

  test('accepts a pending key as first-seen and clears verification', () async {
    await store.evaluate(
      senderId: 'device-a',
      keyId: 'firstKey90_',
      publicKeyBytes: Uint8List.fromList(List<int>.filled(32, 5)),
    );
    await store.markVerified('device-a', 'firstKey90_');
    await store.evaluate(
      senderId: 'device-a',
      keyId: 'secondKey9_',
      publicKeyBytes: Uint8List.fromList(List<int>.filled(32, 6)),
    );

    await store.acceptPending('device-a', 'secondKey9_');
    final identity = (await store.list()).single;

    expect(identity.keyId, 'secondKey9_');
    expect(identity.trustLevel, IdentityTrustLevel.seen);
    expect(identity.pendingKeyId, isNull);
  });

  test('rejects a pending key and keeps the old key', () async {
    await store.evaluate(
      senderId: 'device-a',
      keyId: 'firstKey90_',
      publicKeyBytes: Uint8List.fromList(List<int>.filled(32, 7)),
    );
    await store.evaluate(
      senderId: 'device-a',
      keyId: 'secondKey9_',
      publicKeyBytes: Uint8List.fromList(List<int>.filled(32, 8)),
    );

    await store.rejectPending('device-a', 'secondKey9_');
    final identity = (await store.list()).single;

    expect(identity.keyId, 'firstKey90_');
    expect(identity.pendingKeyId, isNull);
  });

  test('persists trust decisions across store instances', () async {
    await store.evaluate(
      senderId: 'device-a',
      keyId: 'firstKey90_',
      publicKeyBytes: Uint8List.fromList(List<int>.filled(32, 9)),
    );
    await store.markVerified('device-a', 'firstKey90_');

    final reloaded = IdentityTrustStore(values: values);
    final identity = (await reloaded.list()).single;

    expect(identity.keyId, 'firstKey90_');
    expect(identity.trustLevel, IdentityTrustLevel.verified);
  });
}

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
