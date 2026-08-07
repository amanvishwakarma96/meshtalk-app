import 'dart:math';
import 'dart:typed_data';

import 'package:meshtalk_app/core/security/device_agreement_identity.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/room_epoch_key_package.dart';
import 'package:meshtalk_app/core/security/room_join_request.dart';
import 'package:meshtalk_app/core/security/room_membership.dart';
import 'package:meshtalk_app/core/security/room_membership_invite.dart';
import 'package:meshtalk_app/core/security/room_membership_store.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

class RoomMemberSummary {
  const RoomMemberSummary({
    required this.deviceId,
    required this.role,
    required this.epoch,
    required this.signingKeyId,
    required this.agreementKeyId,
    required this.isLocal,
  });

  final String deviceId;
  final RoomMemberRole role;
  final int epoch;
  final String signingKeyId;
  final String? agreementKeyId;
  final bool isLocal;
}

class RoomRotationResult {
  const RoomRotationResult({
    required this.room,
    required this.removedDeviceId,
    required this.memberUpdateCodes,
  });

  final SecureRoom room;
  final String removedDeviceId;
  final Map<String, String> memberUpdateCodes;
}

class RoomMembershipManager {
  RoomMembershipManager({
    required SecureRoomStore roomStore,
    required RoomMembershipStore membershipStore,
    required DeviceIdentity signingIdentity,
    required DeviceAgreementIdentity agreementIdentity,
    RoomMembershipCodec? membershipCodec,
    RoomJoinRequestCodec? joinRequestCodec,
    RoomEpochKeyPackageCodec? keyPackageCodec,
    RoomMembershipInviteCodec? inviteCodec,
    SecureRoomCodeCodec? roomCodeCodec,
    Random? random,
    DateTime Function()? nowUtc,
  })  : _roomStore = roomStore,
        _membershipStore = membershipStore,
        _signingIdentity = signingIdentity,
        _agreementIdentity = agreementIdentity,
        _membershipCodec = membershipCodec ?? RoomMembershipCodec(),
        _joinRequestCodec = joinRequestCodec ?? RoomJoinRequestCodec(),
        _keyPackageCodec = keyPackageCodec ?? RoomEpochKeyPackageCodec(),
        _inviteCodec = inviteCodec ?? RoomMembershipInviteCodec(),
        _roomCodeCodec = roomCodeCodec ?? SecureRoomCodeCodec(),
        _random = random ?? Random.secure(),
        _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()) {
    if (_signingIdentity.deviceId != _agreementIdentity.deviceId) {
      throw ArgumentError('Local signing and agreement identities must match.');
    }
  }

  final SecureRoomStore _roomStore;
  final RoomMembershipStore _membershipStore;
  final DeviceIdentity _signingIdentity;
  final DeviceAgreementIdentity _agreementIdentity;
  final RoomMembershipCodec _membershipCodec;
  final RoomJoinRequestCodec _joinRequestCodec;
  final RoomEpochKeyPackageCodec _keyPackageCodec;
  final RoomMembershipInviteCodec _inviteCodec;
  final SecureRoomCodeCodec _roomCodeCodec;
  final Random _random;
  final DateTime Function() _nowUtc;

  String get localDeviceId => _signingIdentity.deviceId;

  Future<RoomMembership> ensureLocalMembership(SecureRoom room) async {
    final existing = await _membershipStore.membershipFor(
      roomId: room.id,
      deviceId: localDeviceId,
      epoch: room.epoch,
    );
    if (existing != null) {
      _validateLocalMembership(existing);
      return existing;
    }

    final current =
        await _membershipStore.listCurrentEpoch(room.id, room.epoch);
    if (current.isNotEmpty) {
      throw StateError(
        'This device is not authorized for room epoch ${room.epoch}.',
      );
    }

    final owner = await _membershipCodec.issue(
      roomId: room.id,
      epoch: room.epoch,
      memberDeviceId: localDeviceId,
      memberPublicKeyBytes: _signingIdentity.publicKeyBytes,
      memberAgreementPublicKeyBytes: _agreementIdentity.publicKeyBytes,
      role: RoomMemberRole.owner,
      issuedAtUtc: _nowUtc(),
      issuer: _signingIdentity,
    );
    await _membershipStore.replaceEpoch(
      roomId: room.id,
      epoch: room.epoch,
      memberships: <RoomMembership>[owner],
    );
    return owner;
  }

  Future<bool> canLocalSend(SecureRoom room) async {
    try {
      final membership = await ensureLocalMembership(room);
      return membership.epoch == room.epoch &&
          _constantTimeEquals(
            membership.memberPublicKeyBytes,
            _signingIdentity.publicKeyBytes,
          );
    } on StateError {
      return false;
    }
  }

  Future<List<RoomMemberSummary>> listCurrentMembers(SecureRoom room) async {
    final memberships =
        await _membershipStore.listCurrentEpoch(room.id, room.epoch);
    return List<RoomMemberSummary>.unmodifiable(
      memberships.map(
        (membership) => RoomMemberSummary(
          deviceId: membership.memberDeviceId,
          role: membership.role,
          epoch: membership.epoch,
          signingKeyId: _deriveDisplayedKeyId(membership.memberPublicKeyBytes),
          agreementKeyId: membership.memberAgreementKeyId,
          isLocal: membership.memberDeviceId == localDeviceId,
        ),
      ),
    );
  }

  Future<bool> isAuthorizedSender({
    required SecureRoom room,
    required String senderDeviceId,
    required List<int> signingPublicKeyBytes,
  }) async {
    final membership = await _membershipStore.membershipFor(
      roomId: room.id,
      deviceId: senderDeviceId,
      epoch: room.epoch,
    );
    return membership != null &&
        _constantTimeEquals(
          membership.memberPublicKeyBytes,
          signingPublicKeyBytes,
        );
  }

  Future<String> createJoinRequestCode() async {
    final request = await _joinRequestCodec.issue(
      signingIdentity: _signingIdentity,
      agreementIdentity: _agreementIdentity,
      createdAtUtc: _nowUtc(),
    );
    return _joinRequestCodec.encode(request);
  }

  Future<String> issueInvite({
    required SecureRoom room,
    required String joinRequestCode,
  }) async {
    final owner = await ensureLocalMembership(room);
    if (owner.role != RoomMemberRole.owner) {
      throw StateError('Only the room owner can add members.');
    }
    final request = _joinRequestCodec.decode(joinRequestCode);
    if (!await _joinRequestCodec.verify(request)) {
      throw const FormatException('Member join request signature is invalid.');
    }
    if (request.deviceId == localDeviceId) {
      throw StateError('The local owner is already a member of this room.');
    }

    final membership = await _membershipCodec.issue(
      roomId: room.id,
      epoch: room.epoch,
      memberDeviceId: request.deviceId,
      memberPublicKeyBytes: request.signingPublicKeyBytes,
      memberAgreementPublicKeyBytes: request.agreementPublicKeyBytes,
      role: RoomMemberRole.member,
      issuedAtUtc: _nowUtc(),
      issuer: _signingIdentity,
    );
    await _membershipStore.upsert(membership);
    final package = await _keyPackageCodec.issue(
      room: room,
      membership: membership,
      issuer: _signingIdentity,
    );
    return _inviteCodec.encode(
      RoomMembershipInvite(
        ownerMembership: owner,
        memberMembership: membership,
        keyPackage: package,
      ),
    );
  }

  Future<SecureRoom> importInvite(String inviteCode) async {
    final invite = _inviteCodec.decode(inviteCode);
    if (!await _inviteCodec.verify(invite)) {
      throw const FormatException(
          'Membership invite signature chain is invalid.');
    }
    final membership = invite.memberMembership;
    if (membership.memberDeviceId != localDeviceId ||
        !_constantTimeEquals(
          membership.memberPublicKeyBytes,
          _signingIdentity.publicKeyBytes,
        ) ||
        membership.memberAgreementKeyId != _agreementIdentity.keyId ||
        !_constantTimeEquals(
          membership.memberAgreementPublicKeyBytes ?? const <int>[],
          _agreementIdentity.publicKeyBytes,
        )) {
      throw const FormatException(
          'Membership invite belongs to another device.');
    }

    final keyBytes = await _keyPackageCodec.open(
      package: invite.keyPackage,
      recipient: _agreementIdentity,
    );
    final room = await _roomStore.installEpochKey(
      roomId: membership.roomId,
      roomName: invite.keyPackage.roomName,
      epoch: membership.epoch,
      keyId: invite.keyPackage.keyId,
      keyBytes: keyBytes,
      activatedAtUtc: _nowUtc(),
    );
    await _membershipStore.upsert(invite.ownerMembership);
    await _membershipStore.upsert(membership);
    return room;
  }

  Future<RoomRotationResult> removeMember({
    required SecureRoom room,
    required String memberDeviceId,
  }) async {
    final owner = await ensureLocalMembership(room);
    if (owner.role != RoomMemberRole.owner) {
      throw StateError('Only the room owner can remove members.');
    }
    if (memberDeviceId == localDeviceId) {
      throw StateError('The room owner cannot remove itself.');
    }

    final current =
        await _membershipStore.listCurrentEpoch(room.id, room.epoch);
    final target = current
        .where((membership) => membership.memberDeviceId == memberDeviceId)
        .firstOrNull;
    if (target == null) {
      throw StateError('The selected device is not a current room member.');
    }
    final remaining = current
        .where((membership) => membership.memberDeviceId != memberDeviceId)
        .toList(growable: false);
    for (final membership in remaining) {
      if (!membership.supportsEpochKeyUpdates) {
        throw StateError(
          'Member ${membership.memberDeviceId} must be re-invited with an X25519 key before rotation.',
        );
      }
    }

    final keyBytes = _randomBytes(32);
    final rotatedRoom = room.rotateTo(
      newKeyId: await _roomCodeCodec.deriveKeyId(keyBytes),
      newKeyBytes: keyBytes,
      activatedAtUtc: _nowUtc(),
    );
    final nextMemberships = <RoomMembership>[];
    for (final previous in remaining) {
      nextMemberships.add(
        await _membershipCodec.issue(
          roomId: rotatedRoom.id,
          epoch: rotatedRoom.epoch,
          memberDeviceId: previous.memberDeviceId,
          memberPublicKeyBytes: previous.memberPublicKeyBytes,
          memberAgreementPublicKeyBytes: previous.memberAgreementPublicKeyBytes,
          role: previous.role,
          issuedAtUtc: _nowUtc(),
          issuer: _signingIdentity,
        ),
      );
    }

    final nextOwner = nextMemberships
        .where((membership) => membership.role == RoomMemberRole.owner)
        .single;
    final updateCodes = <String, String>{};
    for (final membership in nextMemberships) {
      if (membership.role == RoomMemberRole.owner) {
        continue;
      }
      final package = await _keyPackageCodec.issue(
        room: rotatedRoom,
        membership: membership,
        issuer: _signingIdentity,
      );
      updateCodes[membership.memberDeviceId] = _inviteCodec.encode(
        RoomMembershipInvite(
          ownerMembership: nextOwner,
          memberMembership: membership,
          keyPackage: package,
        ),
      );
    }

    await _membershipStore.replaceEpoch(
      roomId: rotatedRoom.id,
      epoch: rotatedRoom.epoch,
      memberships: nextMemberships,
    );
    final committed = await _roomStore.installEpochKey(
      roomId: rotatedRoom.id,
      roomName: rotatedRoom.name,
      epoch: rotatedRoom.epoch,
      keyId: rotatedRoom.keyId,
      keyBytes: rotatedRoom.keyBytes,
      activatedAtUtc: rotatedRoom.keyActivatedAtUtc,
    );
    return RoomRotationResult(
      room: committed,
      removedDeviceId: memberDeviceId,
      memberUpdateCodes: Map<String, String>.unmodifiable(updateCodes),
    );
  }

  void _validateLocalMembership(RoomMembership membership) {
    if (!_constantTimeEquals(
          membership.memberPublicKeyBytes,
          _signingIdentity.publicKeyBytes,
        ) ||
        membership.memberAgreementKeyId != _agreementIdentity.keyId ||
        !_constantTimeEquals(
          membership.memberAgreementPublicKeyBytes ?? const <int>[],
          _agreementIdentity.publicKeyBytes,
        )) {
      throw StateError(
          'Local room membership does not match this device identity.');
    }
  }

  String _deriveDisplayedKeyId(List<int> keyBytes) {
    var accumulator = 0;
    for (final byte in keyBytes.take(8)) {
      accumulator = ((accumulator << 5) - accumulator + byte) & 0x7fffffff;
    }
    return accumulator.toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
