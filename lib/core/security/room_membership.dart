import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';

class RoomMemberRole {
  const RoomMemberRole._(this.value);

  static const RoomMemberRole owner = RoomMemberRole._('owner');
  static const RoomMemberRole member = RoomMemberRole._('member');

  final String value;

  static RoomMemberRole parse(String value) {
    switch (value) {
      case 'owner':
        return owner;
      case 'member':
        return member;
      default:
        throw FormatException('Unsupported room member role: $value');
    }
  }
}

class RoomMembership {
  RoomMembership({
    required this.roomId,
    required this.epoch,
    required this.memberDeviceId,
    required Uint8List memberPublicKeyBytes,
    required this.role,
    required this.issuedAtUtc,
    required this.issuedByDeviceId,
    required Uint8List issuerPublicKeyBytes,
    required Uint8List signatureBytes,
  })  : memberPublicKeyBytes = Uint8List.fromList(memberPublicKeyBytes),
        issuerPublicKeyBytes = Uint8List.fromList(issuerPublicKeyBytes),
        signatureBytes = Uint8List.fromList(signatureBytes) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(roomId)) {
      throw ArgumentError.value(roomId, 'roomId', 'Invalid room ID.');
    }
    if (epoch < 1) {
      throw ArgumentError.value(epoch, 'epoch', 'Room epoch must be positive.');
    }
    if (this.memberPublicKeyBytes.length != 32 ||
        this.issuerPublicKeyBytes.length != 32) {
      throw ArgumentError('Room membership keys must be Ed25519 public keys.');
    }
    if (this.signatureBytes.length != 64) {
      throw ArgumentError('Room membership signature must contain 64 bytes.');
    }
  }

  final String roomId;
  final int epoch;
  final String memberDeviceId;
  final Uint8List memberPublicKeyBytes;
  final RoomMemberRole role;
  final DateTime issuedAtUtc;
  final String issuedByDeviceId;
  final Uint8List issuerPublicKeyBytes;
  final Uint8List signatureBytes;

  Map<String, Object> get signedFields => <String, Object>{
        'epoch': epoch,
        'issuedAtUtc': issuedAtUtc.toUtc().toIso8601String(),
        'issuedByDeviceId': issuedByDeviceId,
        'issuerPublicKey': base64UrlEncode(issuerPublicKeyBytes),
        'memberDeviceId': memberDeviceId,
        'memberPublicKey': base64UrlEncode(memberPublicKeyBytes),
        'role': role.value,
        'roomId': roomId,
        'version': 1,
      };

  Map<String, Object> toJson() => <String, Object>{
        ...signedFields,
        'signature': base64UrlEncode(signatureBytes),
      };
}

class RoomMembershipCodec {
  RoomMembershipCodec({Ed25519? algorithm})
      : _algorithm = algorithm ?? Ed25519();

  final Ed25519 _algorithm;

  Future<RoomMembership> issue({
    required String roomId,
    required int epoch,
    required String memberDeviceId,
    required List<int> memberPublicKeyBytes,
    required RoomMemberRole role,
    required DateTime issuedAtUtc,
    required DeviceIdentity issuer,
  }) async {
    final unsigned = _canonicalBytes(<String, Object>{
      'epoch': epoch,
      'issuedAtUtc': issuedAtUtc.toUtc().toIso8601String(),
      'issuedByDeviceId': issuer.deviceId,
      'issuerPublicKey': base64UrlEncode(issuer.publicKeyBytes),
      'memberDeviceId': memberDeviceId,
      'memberPublicKey': base64UrlEncode(memberPublicKeyBytes),
      'role': role.value,
      'roomId': roomId,
      'version': 1,
    });
    final signature = await _algorithm.sign(unsigned, keyPair: issuer.keyPair);
    return RoomMembership(
      roomId: roomId,
      epoch: epoch,
      memberDeviceId: memberDeviceId,
      memberPublicKeyBytes: Uint8List.fromList(memberPublicKeyBytes),
      role: role,
      issuedAtUtc: issuedAtUtc.toUtc(),
      issuedByDeviceId: issuer.deviceId,
      issuerPublicKeyBytes: issuer.publicKeyBytes,
      signatureBytes: Uint8List.fromList(signature.bytes),
    );
  }

  Future<bool> verify(RoomMembership membership) {
    return _algorithm.verify(
      _canonicalBytes(membership.signedFields),
      signature: Signature(
        membership.signatureBytes,
        publicKey: SimplePublicKey(
          membership.issuerPublicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }

  RoomMembership decode(String encoded) {
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map<String, dynamic> || raw['version'] != 1) {
        throw const FormatException('Unsupported room membership version.');
      }
      return RoomMembership(
        roomId: raw['roomId'] as String,
        epoch: raw['epoch'] as int,
        memberDeviceId: raw['memberDeviceId'] as String,
        memberPublicKeyBytes:
            Uint8List.fromList(base64Url.decode(raw['memberPublicKey'] as String)),
        role: RoomMemberRole.parse(raw['role'] as String),
        issuedAtUtc: DateTime.parse(raw['issuedAtUtc'] as String).toUtc(),
        issuedByDeviceId: raw['issuedByDeviceId'] as String,
        issuerPublicKeyBytes:
            Uint8List.fromList(base64Url.decode(raw['issuerPublicKey'] as String)),
        signatureBytes:
            Uint8List.fromList(base64Url.decode(raw['signature'] as String)),
      );
    } on Object catch (error) {
      throw FormatException('Room membership is malformed: $error');
    }
  }

  String encode(RoomMembership membership) => jsonEncode(membership.toJson());

  Uint8List _canonicalBytes(Map<String, Object> fields) {
    final keys = fields.keys.toList(growable: false)..sort();
    final canonical = <String, Object>{
      for (final key in keys) key: fields[key]!,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(canonical)));
  }
}
