import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';

void main() {
  late MessageProtector protector;
  late SecureRoom room;
  late DeviceIdentity identity;

  setUp(() async {
    protector = MessageProtector();
    room = await _room(
      keyBytes: List<int>.generate(32, (index) => index),
    );
    identity = await _identity('device-a');
  });

  test('encrypts, signs, and authenticates a message payload', () async {
    final envelope = _envelope(room.id);
    final clearText = Uint8List.fromList(utf8.encode('top secret payload'));

    final protected = await protector.protect(
      envelope: envelope,
      clearText: clearText,
      room: room,
      identity: identity,
    );
    final unprotected = await protector.unprotect(
      envelope: protected,
      room: room,
    );

    expect(protector.isProtectedPayload(protected.payload), isTrue);
    expect(protector.isSignedProtectedPayload(protected.payload), isTrue);
    expect(protected.payload, isNot(clearText));
    expect(_containsSequence(protected.payload, clearText), isFalse);
    expect(unprotected.clearText, clearText);
    expect(
      unprotected.status,
      MessageProtectionStatus.endToEndEncrypted,
    );
    expect(unprotected.senderIdentity?.keyId, identity.keyId);
    expect(unprotected.senderIdentity?.publicKeyBytes, identity.publicKeyBytes);
  });

  test('rejects sender metadata impersonation', () async {
    final protected = await protector.protect(
      envelope: _envelope(room.id),
      clearText: Uint8List.fromList(utf8.encode('authenticated')),
      room: room,
      identity: identity,
    );

    final tampered = protected.copyWith(senderId: 'attacker-device');

    await expectLater(
      protector.unprotect(envelope: tampered, room: room),
      throwsA(
        isA<MessageProtectionException>().having(
          (error) => error.failure,
          'failure',
          MessageProtectionFailure.signatureInvalid,
        ),
      ),
    );
  });

  test('allows relays to decrement hop limit without decrypting', () async {
    final protected = await protector.protect(
      envelope: _envelope(room.id),
      clearText: Uint8List.fromList(utf8.encode('relay-safe')),
      room: room,
      identity: identity,
    );

    final relayed = protected.copyWith(hopLimit: protected.hopLimit - 1);
    final unprotected = await protector.unprotect(
      envelope: relayed,
      room: room,
    );

    expect(utf8.decode(unprotected.clearText), 'relay-safe');
  });

  test('rejects a room with different key material', () async {
    final protected = await protector.protect(
      envelope: _envelope(room.id),
      clearText: Uint8List.fromList(utf8.encode('wrong room')),
      room: room,
      identity: identity,
    );
    final wrongRoom = await _room(
      roomId: room.id,
      keyBytes: List<int>.generate(32, (index) => 255 - index),
    );

    await expectLater(
      protector.unprotect(envelope: protected, room: wrongRoom),
      throwsA(
        isA<MessageProtectionException>().having(
          (error) => error.failure,
          'failure',
          MessageProtectionFailure.keyMismatch,
        ),
      ),
    );
  });

  test('rejects changed ciphertext before decryption', () async {
    final protected = await protector.protect(
      envelope: _envelope(room.id),
      clearText: Uint8List.fromList(utf8.encode('tamper proof')),
      room: room,
      identity: identity,
    );
    final changed = Uint8List.fromList(protected.payload);
    changed[changed.length - 1] ^= 0x01;

    await expectLater(
      protector.unprotect(
        envelope: protected.copyWith(payload: changed),
        room: room,
      ),
      throwsA(
        isA<MessageProtectionException>().having(
          (error) => error.failure,
          'failure',
          MessageProtectionFailure.signatureInvalid,
        ),
      ),
    );
  });

  test('rejects a changed Ed25519 signature', () async {
    final protected = await protector.protect(
      envelope: _envelope(room.id),
      clearText: Uint8List.fromList(utf8.encode('signed')),
      room: room,
      identity: identity,
    );
    final changed = Uint8List.fromList(protected.payload);
    const signatureStart = 4 + 1 + 1 + 8 + 8 + 32 + 24 + 16;
    changed[signatureStart] ^= 0x01;

    await expectLater(
      protector.unprotect(
        envelope: protected.copyWith(payload: changed),
        room: room,
      ),
      throwsA(
        isA<MessageProtectionException>().having(
          (error) => error.failure,
          'failure',
          MessageProtectionFailure.signatureInvalid,
        ),
      ),
    );
  });

  test('rejects a public-key fingerprint mismatch', () async {
    final protected = await protector.protect(
      envelope: _envelope(room.id),
      clearText: Uint8List.fromList(utf8.encode('identity-bound')),
      room: room,
      identity: identity,
    );
    final changed = Uint8List.fromList(protected.payload);
    const identityKeyIdStart = 4 + 1 + 1 + 8;
    changed[identityKeyIdStart] ^= 0x01;

    await expectLater(
      protector.unprotect(
        envelope: protected.copyWith(payload: changed),
        room: room,
      ),
      throwsA(
        isA<MessageProtectionException>().having(
          (error) => error.failure,
          'failure',
          MessageProtectionFailure.identityMalformed,
        ),
      ),
    );
  });

  test('requires the envelope sender to match the signing identity', () async {
    final otherIdentity = await _identity('device-b');

    await expectLater(
      protector.protect(
        envelope: _envelope(room.id),
        clearText: Uint8List.fromList(utf8.encode('impersonation')),
        room: room,
        identity: otherIdentity,
      ),
      throwsArgumentError,
    );
  });

  test('allows plaintext only for explicit local history reads', () async {
    final legacy = _envelope(
      room.id,
      payload: Uint8List.fromList(utf8.encode('old history')),
    );

    await expectLater(
      protector.unprotect(envelope: legacy, room: room),
      throwsA(
        isA<MessageProtectionException>().having(
          (error) => error.failure,
          'failure',
          MessageProtectionFailure.malformed,
        ),
      ),
    );

    final unprotected = await protector.unprotect(
      envelope: legacy,
      room: room,
      allowLegacy: true,
    );
    expect(utf8.decode(unprotected.clearText), 'old history');
    expect(
      unprotected.status,
      MessageProtectionStatus.legacyUnencrypted,
    );
    expect(unprotected.senderIdentity, isNull);
  });
}

Future<SecureRoom> _room({
  String roomId = 'roomIdentifier1234567890',
  required List<int> keyBytes,
}) async {
  final codec = SecureRoomCodeCodec();
  return SecureRoom(
    id: roomId,
    name: 'Test room',
    keyId: await codec.deriveKeyId(keyBytes),
    keyBytes: Uint8List.fromList(keyBytes),
    createdAtUtc: DateTime.utc(2026, 8, 5),
  );
}

Future<DeviceIdentity> _identity(String deviceId) async {
  final extracted = await (await Ed25519().newKeyPair()).extract();
  final digest = await Sha256().hash(extracted.publicKey.bytes);
  return DeviceIdentity(
    deviceId: deviceId,
    keyId: base64UrlEncode(digest.bytes.take(8).toList()).replaceAll('=', ''),
    publicKeyBytes: Uint8List.fromList(extracted.publicKey.bytes),
    privateKeyBytes: Uint8List.fromList(extracted.bytes),
    createdAtUtc: DateTime.utc(2026, 8, 6),
  );
}

MessageEnvelope _envelope(String roomId, {Uint8List? payload}) {
  return MessageEnvelope(
    id: '550e8400-e29b-41d4-a716-446655440000',
    senderId: 'device-a',
    roomId: roomId,
    timestampUtc: DateTime.utc(2026, 8, 5, 12),
    hopLimit: 4,
    payload: payload ?? Uint8List(0),
  );
}

bool _containsSequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return false;
  }
  for (var start = 0; start <= haystack.length - needle.length; start += 1) {
    var matches = true;
    for (var index = 0; index < needle.length; index += 1) {
      if (haystack[start + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}
