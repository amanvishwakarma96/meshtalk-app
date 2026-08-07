import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/security/device_agreement_identity.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/room_membership_manager.dart';
import 'package:meshtalk_app/core/security/room_membership_store.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

void main() {
  test('invites members and rotates away a removed member', () async {
    final ownerSigning = await _signingIdentity('owner-device');
    final ownerAgreement = await _agreementIdentity('owner-device');
    final memberASigning = await _signingIdentity('member-a');
    final memberAAgreement = await _agreementIdentity('member-a');
    final memberBSigning = await _signingIdentity('member-b');
    final memberBAgreement = await _agreementIdentity('member-b');

    final ownerValues = _MemorySecureValueStore();
    final ownerRoomStore = SecureRoomStore(values: ownerValues);
    final ownerMembershipStore = RoomMembershipStore(values: ownerValues);
    final ownerManager = RoomMembershipManager(
      roomStore: ownerRoomStore,
      membershipStore: ownerMembershipStore,
      signingIdentity: ownerSigning,
      agreementIdentity: ownerAgreement,
      nowUtc: () => DateTime.utc(2026, 8, 7, 12),
    );
    final room = await ownerRoomStore.createRoom('Rotation room');
    await ownerManager.ensureLocalMembership(room);

    final memberAValues = _MemorySecureValueStore();
    final memberAManager = RoomMembershipManager(
      roomStore: SecureRoomStore(values: memberAValues),
      membershipStore: RoomMembershipStore(values: memberAValues),
      signingIdentity: memberASigning,
      agreementIdentity: memberAAgreement,
    );
    final memberBValues = _MemorySecureValueStore();
    final memberBRoomStore = SecureRoomStore(values: memberBValues);
    final memberBManager = RoomMembershipManager(
      roomStore: memberBRoomStore,
      membershipStore: RoomMembershipStore(values: memberBValues),
      signingIdentity: memberBSigning,
      agreementIdentity: memberBAgreement,
    );

    final inviteA = await ownerManager.issueInvite(
      room: room,
      joinRequestCode: await memberAManager.createJoinRequestCode(),
    );
    final inviteB = await ownerManager.issueInvite(
      room: room,
      joinRequestCode: await memberBManager.createJoinRequestCode(),
    );
    final memberARoom = await memberAManager.importInvite(inviteA);
    final memberBRoom = await memberBManager.importInvite(inviteB);

    expect(memberARoom.epoch, 1);
    expect(memberBRoom.keyId, room.keyId);
    expect(await ownerManager.listCurrentMembers(room), hasLength(3));

    final rotation = await ownerManager.removeMember(
      room: room,
      memberDeviceId: memberASigning.deviceId,
    );

    expect(rotation.room.epoch, 2);
    expect(rotation.room.keyId, isNot(room.keyId));
    expect(rotation.memberUpdateCodes.keys, <String>[memberBSigning.deviceId]);
    expect(rotation.memberUpdateCodes, isNot(contains(memberASigning.deviceId)));
    expect(rotation.room.historicalKeys.single.keyId, room.keyId);

    final updatedMemberBRoom = await memberBManager.importInvite(
      rotation.memberUpdateCodes[memberBSigning.deviceId]!,
    );
    expect(updatedMemberBRoom.epoch, 2);
    expect(updatedMemberBRoom.keyId, rotation.room.keyId);
    expect(updatedMemberBRoom.historicalKeys.single.keyId, room.keyId);

    await expectLater(
      memberAManager.importInvite(
        rotation.memberUpdateCodes[memberBSigning.deviceId]!,
      ),
      throwsA(isA<FormatException>()),
    );

    final currentMembers = await ownerManager.listCurrentMembers(rotation.room);
    expect(
      currentMembers.map((member) => member.deviceId),
      containsAll(<String>[ownerSigning.deviceId, memberBSigning.deviceId]),
    );
    expect(
      currentMembers.map((member) => member.deviceId),
      isNot(contains(memberASigning.deviceId)),
    );

    final protector = MessageProtector();
    final protected = await protector.protect(
      envelope: MessageEnvelope(
        id: '550e8400-e29b-41d4-a716-446655440200',
        senderId: ownerSigning.deviceId,
        roomId: rotation.room.id,
        timestampUtc: DateTime.utc(2026, 8, 7, 12, 30),
        hopLimit: 4,
        payload: Uint8List(0),
      ),
      clearText: Uint8List.fromList(utf8.encode('after removal')),
      room: rotation.room,
      identity: ownerSigning,
    );
    await expectLater(
      protector.unprotect(envelope: protected, room: memberARoom),
      throwsA(isA<MessageProtectionException>()),
    );
    final memberBRead = await protector.unprotect(
      envelope: protected,
      room: updatedMemberBRoom,
    );
    expect(utf8.decode(memberBRead.clearText), 'after removal');
  });

  test('rejects a join request with modified key material', () async {
    final ownerSigning = await _signingIdentity('owner-device');
    final ownerAgreement = await _agreementIdentity('owner-device');
    final memberSigning = await _signingIdentity('member-device');
    final memberAgreement = await _agreementIdentity('member-device');
    final ownerValues = _MemorySecureValueStore();
    final ownerRoomStore = SecureRoomStore(values: ownerValues);
    final ownerManager = RoomMembershipManager(
      roomStore: ownerRoomStore,
      membershipStore: RoomMembershipStore(values: ownerValues),
      signingIdentity: ownerSigning,
      agreementIdentity: ownerAgreement,
    );
    final room = await ownerRoomStore.createRoom('Tamper room');
    await ownerManager.ensureLocalMembership(room);

    final memberValues = _MemorySecureValueStore();
    final memberManager = RoomMembershipManager(
      roomStore: SecureRoomStore(values: memberValues),
      membershipStore: RoomMembershipStore(values: memberValues),
      signingIdentity: memberSigning,
      agreementIdentity: memberAgreement,
    );
    final request = await memberManager.createJoinRequestCode();
    final parts = request.split('.');
    final padding = '=' * ((4 - parts[1].length % 4) % 4);
    final raw = jsonDecode(
      utf8.decode(base64Url.decode('${parts[1]}$padding')),
    ) as Map<String, dynamic>;
    raw['agreementKeyId'] = 'AAAAAAAAAAA';
    final tampered =
        'MTJ1.${base64UrlEncode(utf8.encode(jsonEncode(raw))).replaceAll('=', '')}';

    await expectLater(
      ownerManager.issueInvite(room: room, joinRequestCode: tampered),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<DeviceIdentity> _signingIdentity(String deviceId) async {
  final extracted = await (await Ed25519().newKeyPair()).extract();
  final digest = await Sha256().hash(extracted.publicKey.bytes);
  return DeviceIdentity(
    deviceId: deviceId,
    keyId: base64UrlEncode(digest.bytes.take(8).toList()).replaceAll('=', ''),
    publicKeyBytes: Uint8List.fromList(extracted.publicKey.bytes),
    privateKeyBytes: Uint8List.fromList(extracted.bytes),
    createdAtUtc: DateTime.utc(2026, 8, 7),
  );
}

Future<DeviceAgreementIdentity> _agreementIdentity(String deviceId) async {
  final extracted = await (await X25519().newKeyPair()).extract();
  final digest = await Sha256().hash(extracted.publicKey.bytes);
  return DeviceAgreementIdentity(
    deviceId: deviceId,
    keyId: base64UrlEncode(digest.bytes.take(8).toList()).replaceAll('=', ''),
    publicKeyBytes: Uint8List.fromList(extracted.publicKey.bytes),
    privateKeyBytes: Uint8List.fromList(extracted.bytes),
    createdAtUtc: DateTime.utc(2026, 8, 7),
  );
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
