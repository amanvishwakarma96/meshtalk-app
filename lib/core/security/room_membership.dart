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
    return switch (value) {
      'owner' => owner,
      'member' => member,
      _ => throw FormatException('Unsupported room member role: $value'),
    };
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
    this.version = 1,
    this.memberAgreementKeyId,
    Uint8List? memberAgreementPublicKeyBytes,
  })  : memberPublicKeyBytes = Uint8List.fromList(memberPublicKeyBytes),
        memberAgreementPublicKeyBytes = memberAgreementPublicKeyBytes == null
            ? null
            : Uint8List.fromList(memberAgreementPublicKeyBytes),
        issuerPublicKeyBytes = Uint8List.fromList(issuerPublicKeyBytes),
        signatureBytes = Uint8List.fromList(signatureBytes) {
    if (version != 1 && version != 2) {
      throw ArgumentError.value(
          version, 'version', 'Unsupported membership version.');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(roomId)) {
      throw ArgumentError.value(roomId, 'roomId', 'Invalid room ID.');
    }
    if (epoch < 1) {
      throw ArgumentError.value(epoch, 'epoch', 'Room epoch must be positive.');
    }
    if (memberDeviceId.trim().isEmpty || issuedByDeviceId.trim().isEmpty) {
      throw ArgumentError('Membership device identifiers must not be empty.');
    }
    if (this.memberPublicKeyBytes.length != 32 ||
        this.issuerPublicKeyBytes.length != 32) {
      throw ArgumentError('Room membership keys must be Ed25519 public keys.');
    }
    if (version == 2) {
      if (memberAgreementKeyId == null ||
          !RegExp(r'^[A-Za-z0-9_-]{8,24}$').hasMatch(memberAgreementKeyId!)) {
        throw ArgumentError(
            'Version 2 membership needs a valid agreement key ID.');
      }
      if (this.memberAgreementPublicKeyBytes?.length != 32) {
        throw ArgumentError(
          'Version 2 membership needs a 32-byte X25519 public key.',
        );
      }
    } else if (memberAgreementKeyId != null ||
        this.memberAgreementPublicKeyBytes != null) {
      throw ArgumentError(
          'Version 1 membership cannot contain agreement keys.');
    }
    if (this.signatureBytes.length != 64) {
      throw ArgumentError('Room membership signature must contain 64 bytes.');
    }
  }

  final int version;
  final String roomId;
  final int epoch;
  final String memberDeviceId;
  final Uint8List memberPublicKeyBytes;
  final String? memberAgreementKeyId;
  final Uint8List? memberAgreementPublicKeyBytes;
  final RoomMemberRole role;
  final DateTime issuedAtUtc;
  final String issuedByDeviceId;
  final Uint8List issuerPublicKeyBytes;
  final Uint8List signatureBytes;

  bool get supportsEpochKeyUpdates =>
      version >= 2 && memberAgreementPublicKeyBytes != null;

  Map<String, Object> get signedFields => <String, Object>{
        'epoch': epoch,
        'issuedAtUtc': issuedAtUtc.toUtc().toIso8601String(),
        'issuedByDeviceId': issuedByDeviceId,
        'issuerPublicKey': base64UrlEncode(issuerPublicKeyBytes),
        if (memberAgreementKeyId != null)
          'memberAgreementKeyId': memberAgreementKeyId!,
        if (memberAgreementPublicKeyBytes != null)
          'memberAgreementPublicKey':
              base64UrlEncode(memberAgreementPublicKeyBytes!),
        'memberDeviceId': memberDeviceId,
        'memberPublicKey': base64UrlEncode(memberPublicKeyBytes),
        'role': role.value,
        'roomId': roomId,
        'version': version,
      };

  Map<String, Object> toJson() => <String, Object>{
        ...signedFields,
        'signature': base64UrlEncode(signatureBytes),
      };
}

class RoomMembershipCodec {
  RoomMembershipCodec({
    Ed25519? algorithm,
    HashAlgorithm? hashAlgorithm,
  })  : _algorithm = algorithm ?? Ed25519(),
        _hashAlgorithm = hashAlgorithm ?? Sha256();

  final Ed25519 _algorithm;
  final HashAlgorithm _hashAlgorithm;

  Future<RoomMembership> issue({
    required String roomId,
    required int epoch,
    required String memberDeviceId,
    required List<int> memberPublicKeyBytes,
    required RoomMemberRole role,
    required DateTime issuedAtUtc,
    required DeviceIdentity issuer,
    List<int>? memberAgreementPublicKeyBytes,
  }) async {
    final version = memberAgreementPublicKeyBytes == null ? 1 : 2;
    final agreementKeyId = memberAgreementPublicKeyBytes == null
        ? null
        : await _deriveKeyId(memberAgreementPublicKeyBytes);
    final unsignedFields = <String, Object>{
      'epoch': epoch,
      'issuedAtUtc': issuedAtUtc.toUtc().toIso8601String(),
      'issuedByDeviceId': issuer.deviceId,
      'issuerPublicKey': base64UrlEncode(issuer.publicKeyBytes),
      if (agreementKeyId != null) 'memberAgreementKeyId': agreementKeyId,
      if (memberAgreementPublicKeyBytes != null)
        'memberAgreementPublicKey':
            base64UrlEncode(memberAgreementPublicKeyBytes),
      'memberDeviceId': memberDeviceId,
      'memberPublicKey': base64UrlEncode(memberPublicKeyBytes),
      'role': role.value,
      'roomId': roomId,
      'version': version,
    };
    final issuerPublicKey = SimplePublicKey(
      issuer.publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final issuerKeyPair = SimpleKeyPairData(
      issuer.privateKeyBytes,
      publicKey: issuerPublicKey,
      type: KeyPairType.ed25519,
    );
    final signature = await _algorithm.sign(
      _canonicalBytes(unsignedFields),
      keyPair: issuerKeyPair,
    );
    return RoomMembership(
      version: version,
      roomId: roomId,
      epoch: epoch,
      memberDeviceId: memberDeviceId,
      memberPublicKeyBytes: Uint8List.fromList(memberPublicKeyBytes),
      memberAgreementKeyId: agreementKeyId,
      memberAgreementPublicKeyBytes: memberAgreementPublicKeyBytes == null
          ? null
          : Uint8List.fromList(memberAgreementPublicKeyBytes),
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
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Room membership must be an object.');
      }
      final version = raw['version'];
      if (version != 1 && version != 2) {
        throw const FormatException('Unsupported room membership version.');
      }
      final agreementKeyId = raw['memberAgreementKeyId'];
      final agreementPublicKey = raw['memberAgreementPublicKey'];
      return RoomMembership(
        version: version as int,
        roomId: raw['roomId'] as String,
        epoch: raw['epoch'] as int,
        memberDeviceId: raw['memberDeviceId'] as String,
        memberPublicKeyBytes: Uint8List.fromList(
          base64Url.decode(raw['memberPublicKey'] as String),
        ),
        memberAgreementKeyId: agreementKeyId as String?,
        memberAgreementPublicKeyBytes: agreementPublicKey == null
            ? null
            : Uint8List.fromList(
                base64Url.decode(agreementPublicKey as String)),
        role: RoomMemberRole.parse(raw['role'] as String),
        issuedAtUtc: DateTime.parse(raw['issuedAtUtc'] as String).toUtc(),
        issuedByDeviceId: raw['issuedByDeviceId'] as String,
        issuerPublicKeyBytes: Uint8List.fromList(
          base64Url.decode(raw['issuerPublicKey'] as String),
        ),
        signatureBytes: Uint8List.fromList(
          base64Url.decode(raw['signature'] as String),
        ),
      );
    } on Object catch (error) {
      throw FormatException('Room membership is malformed: $error');
    }
  }

  String encode(RoomMembership membership) => jsonEncode(membership.toJson());

  Future<String> _deriveKeyId(List<int> publicKeyBytes) async {
    if (publicKeyBytes.length != 32) {
      throw ArgumentError.value(
        publicKeyBytes.length,
        'memberAgreementPublicKeyBytes',
        'X25519 public keys must contain exactly 32 bytes.',
      );
    }
    final digest = await _hashAlgorithm.hash(publicKeyBytes);
    return base64UrlEncode(digest.bytes.take(8).toList()).replaceAll('=', '');
  }

  Uint8List _canonicalBytes(Map<String, Object> fields) {
    final keys = fields.keys.toList(growable: false)..sort();
    final canonical = <String, Object>{
      for (final key in keys) key: fields[key]!,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(canonical)));
  }
}
