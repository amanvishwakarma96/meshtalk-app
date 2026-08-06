import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/identity_trust_store.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:meshtalk_app/features/chat/data/chat_session.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';

import '../../../helpers/fake_ble_chat.dart';
import '../../../helpers/fake_message_store.dart';

void main() {
  test('re-signs queued version-1 ciphertext before transport restoration',
      () async {
    final room = await _room();
    final identity = await _identity(_profile.deviceId);
    final protector = MessageProtector();
    final radio = FakeBleRadio();
    final transport = FakeChatTransport(radio);
    final store = FakeMessageStore();
    final legacyEnvelope = await _legacyV1Envelope(
      room: room,
      clearText: 'queued from PR 9',
    );
    await store.upsert(
      StoredChatMessage(
        envelope: legacyEnvelope,
        senderLabel: _profile.displayName,
        direction: StoredMessageDirection.outgoing,
        deliveryStatus: StoredDeliveryStatus.queued,
      ),
    );
    final session = ChatSession(
      profile: _profile,
      secureRoom: room,
      deviceIdentity: identity,
      identityTrustStore: IdentityTrustStore(
        values: _MemorySecureValueStore(),
      ),
      messageProtector: protector,
      radio: radio,
      bleTransport: transport,
      transportManager: TransportManager(
        transports: <ChatTransport>[transport],
      ),
      messageStore: store,
      openAppSettings: () async {},
    );

    try {
      await session.initialize();

      expect(session.state.messages.single.text, 'queued from PR 9');
      expect(
        session.state.messages.single.protectionStatus,
        MessageProtectionStatus.encryptedLegacyIdentity,
      );
      expect(
        session.state.messages.single.identityStatus,
        MessageIdentityStatus.legacyUnsigned,
      );

      final migrated = store.messages.single.envelope;
      expect(protector.isSignedProtectedPayload(migrated.payload), isTrue);
      final unprotected = await protector.unprotect(
        envelope: migrated,
        room: room,
      );
      expect(utf8.decode(unprotected.clearText), 'queued from PR 9');
      expect(unprotected.senderIdentity?.keyId, identity.keyId);
    } finally {
      await session.close();
      await transport.close();
      await radio.close();
    }
  });
}

const LocalProfile _profile = LocalProfile(
  deviceId: 'device-local',
  displayName: 'Trail Phone',
);

Future<SecureRoom> _room() async {
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
  return SecureRoom(
    id: 'secureRoomIdentifier1234',
    name: 'Family mesh',
    keyId: await SecureRoomCodeCodec().deriveKeyId(key),
    keyBytes: key,
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

Future<MessageEnvelope> _legacyV1Envelope({
  required SecureRoom room,
  required String clearText,
}) async {
  final envelope = MessageEnvelope(
    id: '550e8400-e29b-41d4-a716-446655440090',
    senderId: _profile.deviceId,
    roomId: room.id,
    timestampUtc: DateTime.utc(2026, 8, 5, 12),
    hopLimit: 4,
    payload: Uint8List(0),
  );
  final secretBox = await Xchacha20.poly1305Aead().encrypt(
    utf8.encode(clearText),
    secretKey: SecretKey(room.keyBytes),
    aad: _legacyAssociatedData(envelope),
  );
  final keyId = _decodeBase64Url(room.keyId);
  final payload = (BytesBuilder(copy: false)
        ..add(const <int>[0x4d, 0x54, 0x45, 0x31])
        ..addByte(1)
        ..addByte(1)
        ..add(keyId)
        ..add(secretBox.nonce)
        ..add(secretBox.mac.bytes)
        ..add(secretBox.cipherText))
      .takeBytes();
  return envelope.copyWith(payload: payload);
}

Uint8List _legacyAssociatedData(MessageEnvelope envelope) {
  final timestamp = envelope.timestampUtc.toUtc().microsecondsSinceEpoch;
  return Uint8List.fromList(
    utf8.encode(
      'meshtalk-e2ee-v1|${_field(envelope.id)}|'
      '${_field(envelope.senderId)}|${_field(envelope.roomId)}|$timestamp',
    ),
  );
}

String _field(String value) => '${utf8.encode(value).length}:$value';

List<int> _decodeBase64Url(String value) {
  final padding = '=' * ((4 - value.length % 4) % 4);
  return base64Url.decode('$value$padding');
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
