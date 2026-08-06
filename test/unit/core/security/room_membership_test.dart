import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/security/device_identity_store.dart';
import 'package:meshtalk_app/core/security/room_membership.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

void main() {
  test('issues, encodes, decodes, and verifies a member certificate', () async {
    final values = MemorySecureValueStore();
    final issuer = await DeviceIdentityStore(
      values: values,
      random: Random(13),
    ).loadOrCreate('ownerDeviceIdentifier1');
    final member = await DeviceIdentityStore(
      values: MemorySecureValueStore(),
      random: Random(17),
    ).loadOrCreate('memberDeviceIdentifier1');
    final codec = RoomMembershipCodec();

    final issued = await codec.issue(
      roomId: 'secureRoomIdentifier1234',
      epoch: 1,
      memberDeviceId: member.deviceId,
      memberPublicKeyBytes: member.publicKeyBytes,
      role: RoomMemberRole.member,
      issuedAtUtc: DateTime.utc(2026, 8, 6, 9),
      issuer: issuer,
    );
    final decoded = codec.decode(codec.encode(issued));

    expect(decoded.roomId, issued.roomId);
    expect(decoded.memberDeviceId, member.deviceId);
    expect(decoded.issuedByDeviceId, issuer.deviceId);
    expect(await codec.verify(decoded), isTrue);
  });

  test('rejects signed-field tampering', () async {
    final issuer = await DeviceIdentityStore(
      values: MemorySecureValueStore(),
      random: Random(23),
    ).loadOrCreate('ownerDeviceIdentifier1');
    final member = await DeviceIdentityStore(
      values: MemorySecureValueStore(),
      random: Random(29),
    ).loadOrCreate('memberDeviceIdentifier1');
    final codec = RoomMembershipCodec();
    final issued = await codec.issue(
      roomId: 'secureRoomIdentifier1234',
      epoch: 1,
      memberDeviceId: member.deviceId,
      memberPublicKeyBytes: member.publicKeyBytes,
      role: RoomMemberRole.member,
      issuedAtUtc: DateTime.utc(2026, 8, 6, 9),
      issuer: issuer,
    );

    final tampered = RoomMembership(
      roomId: issued.roomId,
      epoch: 2,
      memberDeviceId: issued.memberDeviceId,
      memberPublicKeyBytes: issued.memberPublicKeyBytes,
      role: issued.role,
      issuedAtUtc: issued.issuedAtUtc,
      issuedByDeviceId: issued.issuedByDeviceId,
      issuerPublicKeyBytes: issued.issuerPublicKeyBytes,
      signatureBytes: issued.signatureBytes,
    );

    expect(await codec.verify(tampered), isFalse);
  });

  test('rejects signature substitution from another owner', () async {
    final firstOwner = await DeviceIdentityStore(
      values: MemorySecureValueStore(),
      random: Random(31),
    ).loadOrCreate('firstOwnerIdentifier12');
    final secondOwner = await DeviceIdentityStore(
      values: MemorySecureValueStore(),
      random: Random(37),
    ).loadOrCreate('secondOwnerIdentifier1');
    final codec = RoomMembershipCodec();
    final issued = await codec.issue(
      roomId: 'secureRoomIdentifier1234',
      epoch: 1,
      memberDeviceId: firstOwner.deviceId,
      memberPublicKeyBytes: firstOwner.publicKeyBytes,
      role: RoomMemberRole.owner,
      issuedAtUtc: DateTime.utc(2026, 8, 6, 9),
      issuer: firstOwner,
    );

    final substituted = RoomMembership(
      roomId: issued.roomId,
      epoch: issued.epoch,
      memberDeviceId: issued.memberDeviceId,
      memberPublicKeyBytes: issued.memberPublicKeyBytes,
      role: issued.role,
      issuedAtUtc: issued.issuedAtUtc,
      issuedByDeviceId: secondOwner.deviceId,
      issuerPublicKeyBytes: secondOwner.publicKeyBytes,
      signatureBytes: issued.signatureBytes,
    );

    expect(await codec.verify(substituted), isFalse);
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
