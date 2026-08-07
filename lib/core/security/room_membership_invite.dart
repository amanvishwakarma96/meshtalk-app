import 'dart:convert';

import 'package:meshtalk_app/core/security/room_epoch_key_package.dart';
import 'package:meshtalk_app/core/security/room_membership.dart';

class RoomMembershipInvite {
  const RoomMembershipInvite({
    required this.ownerMembership,
    required this.memberMembership,
    required this.keyPackage,
  });

  final RoomMembership ownerMembership;
  final RoomMembership memberMembership;
  final RoomEpochKeyPackage keyPackage;
}

class RoomMembershipInviteCodec {
  RoomMembershipInviteCodec({
    RoomMembershipCodec? membershipCodec,
    RoomEpochKeyPackageCodec? keyPackageCodec,
  })  : _membershipCodec = membershipCodec ?? RoomMembershipCodec(),
        _keyPackageCodec = keyPackageCodec ?? RoomEpochKeyPackageCodec();

  static const String _prefix = 'MTI1';
  final RoomMembershipCodec _membershipCodec;
  final RoomEpochKeyPackageCodec _keyPackageCodec;

  String encode(RoomMembershipInvite invite) {
    _validateConsistency(invite);
    final payload = base64UrlEncode(
      utf8.encode(
        jsonEncode(<String, Object>{
          'version': 1,
          'ownerMembership': invite.ownerMembership.toJson(),
          'memberMembership': invite.memberMembership.toJson(),
          'keyPackage': invite.keyPackage.toJson(),
        }),
      ),
    ).replaceAll('=', '');
    return '$_prefix.$payload';
  }

  RoomMembershipInvite decode(String rawCode) {
    final code = rawCode.trim();
    final parts = code.split('.');
    if (parts.length != 2 || parts[0] != _prefix) {
      throw const FormatException('Membership invite has an invalid format.');
    }
    try {
      final padding = '=' * ((4 - parts[1].length % 4) % 4);
      final raw = jsonDecode(
        utf8.decode(base64Url.decode('${parts[1]}$padding')),
      );
      if (raw is! Map<String, dynamic> || raw['version'] != 1) {
        throw const FormatException('Unsupported membership invite version.');
      }
      final ownerRaw = raw['ownerMembership'];
      final memberRaw = raw['memberMembership'];
      final keyPackageRaw = raw['keyPackage'];
      if (ownerRaw is! Map<String, dynamic> ||
          memberRaw is! Map<String, dynamic> ||
          keyPackageRaw is! Map<String, dynamic>) {
        throw const FormatException('Membership invite is malformed.');
      }
      final invite = RoomMembershipInvite(
        ownerMembership: _membershipCodec.decode(jsonEncode(ownerRaw)),
        memberMembership: _membershipCodec.decode(jsonEncode(memberRaw)),
        keyPackage: _keyPackageCodec.decode(
          'MTK1.${base64UrlEncode(utf8.encode(jsonEncode(keyPackageRaw))).replaceAll('=', '')}',
        ),
      );
      _validateConsistency(invite);
      return invite;
    } on Object catch (error) {
      throw FormatException('Membership invite is malformed: $error');
    }
  }

  Future<bool> verify(RoomMembershipInvite invite) async {
    try {
      _validateConsistency(invite);
    } on Object {
      return false;
    }
    if (!await _membershipCodec.verify(invite.ownerMembership) ||
        !await _membershipCodec.verify(invite.memberMembership) ||
        !await _keyPackageCodec.verify(invite.keyPackage)) {
      return false;
    }
    return _constantTimeEquals(
          invite.ownerMembership.memberPublicKeyBytes,
          invite.ownerMembership.issuerPublicKeyBytes,
        ) &&
        _constantTimeEquals(
          invite.ownerMembership.issuerPublicKeyBytes,
          invite.memberMembership.issuerPublicKeyBytes,
        ) &&
        _constantTimeEquals(
          invite.ownerMembership.issuerPublicKeyBytes,
          invite.keyPackage.issuerPublicKeyBytes,
        );
  }

  void _validateConsistency(RoomMembershipInvite invite) {
    final owner = invite.ownerMembership;
    final member = invite.memberMembership;
    final package = invite.keyPackage;
    if (owner.role != RoomMemberRole.owner ||
        owner.memberDeviceId != owner.issuedByDeviceId ||
        owner.roomId != member.roomId ||
        owner.roomId != package.roomId ||
        owner.epoch != member.epoch ||
        owner.epoch != package.epoch ||
        member.memberDeviceId != package.memberDeviceId ||
        member.memberAgreementKeyId != package.memberAgreementKeyId ||
        member.issuedByDeviceId != owner.memberDeviceId ||
        package.issuedByDeviceId != owner.memberDeviceId) {
      throw const FormatException(
        'Membership invite does not contain one consistent owner-authorized epoch.',
      );
    }
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
