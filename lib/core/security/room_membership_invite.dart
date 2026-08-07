import 'dart:convert';

import 'package:meshtalk_app/core/security/room_epoch_key_package.dart';
import 'package:meshtalk_app/core/security/room_membership.dart';

class RoomMembershipInvite {
  const RoomMembershipInvite({
    required this.membership,
    required this.keyPackage,
  });

  final RoomMembership membership;
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
          'membership': invite.membership.toJson(),
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
      final membershipRaw = raw['membership'];
      final keyPackageRaw = raw['keyPackage'];
      if (membershipRaw is! Map<String, dynamic> ||
          keyPackageRaw is! Map<String, dynamic>) {
        throw const FormatException('Membership invite is malformed.');
      }
      final invite = RoomMembershipInvite(
        membership: _membershipCodec.decode(jsonEncode(membershipRaw)),
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
    if (!await _membershipCodec.verify(invite.membership) ||
        !await _keyPackageCodec.verify(invite.keyPackage)) {
      return false;
    }
    return _constantTimeEquals(
      invite.membership.issuerPublicKeyBytes,
      invite.keyPackage.issuerPublicKeyBytes,
    );
  }

  void _validateConsistency(RoomMembershipInvite invite) {
    final membership = invite.membership;
    final package = invite.keyPackage;
    if (membership.roomId != package.roomId ||
        membership.epoch != package.epoch ||
        membership.memberDeviceId != package.memberDeviceId ||
        membership.memberAgreementKeyId != package.memberAgreementKeyId ||
        membership.issuedByDeviceId != package.issuedByDeviceId) {
      throw const FormatException(
        'Membership certificate and room key package do not match.',
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
