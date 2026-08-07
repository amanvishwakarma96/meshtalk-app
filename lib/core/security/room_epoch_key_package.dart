import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshtalk_app/core/security/device_agreement_identity.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/room_membership.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';

class RoomEpochKeyPackage {
  RoomEpochKeyPackage({
    required this.roomId,
    required this.roomName,
    required this.epoch,
    required this.keyId,
    required this.memberDeviceId,
    required this.memberAgreementKeyId,
    required this.issuedByDeviceId,
    required Uint8List issuerPublicKeyBytes,
    required Uint8List ephemeralPublicKeyBytes,
    required Uint8List nonceBytes,
    required Uint8List macBytes,
    required Uint8List cipherTextBytes,
    required Uint8List signatureBytes,
  })  : issuerPublicKeyBytes = Uint8List.fromList(issuerPublicKeyBytes),
        ephemeralPublicKeyBytes = Uint8List.fromList(ephemeralPublicKeyBytes),
        nonceBytes = Uint8List.fromList(nonceBytes),
        macBytes = Uint8List.fromList(macBytes),
        cipherTextBytes = Uint8List.fromList(cipherTextBytes),
        signatureBytes = Uint8List.fromList(signatureBytes) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(roomId)) {
      throw ArgumentError.value(roomId, 'roomId', 'Invalid room ID.');
    }
    if (roomName.trim().length < 2 || roomName.trim().length > 32) {
      throw ArgumentError.value(roomName, 'roomName', 'Invalid room name.');
    }
    if (epoch < 1) {
      throw ArgumentError.value(epoch, 'epoch', 'Room epoch must be positive.');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{8,24}$').hasMatch(keyId) ||
        !RegExp(r'^[A-Za-z0-9_-]{8,24}$').hasMatch(memberAgreementKeyId)) {
      throw ArgumentError('Epoch package contains an invalid key identifier.');
    }
    if (memberDeviceId.trim().isEmpty || issuedByDeviceId.trim().isEmpty) {
      throw ArgumentError('Epoch package device identifiers must not be empty.');
    }
    if (this.issuerPublicKeyBytes.length != 32 ||
        this.ephemeralPublicKeyBytes.length != 32) {
      throw ArgumentError('Epoch package public keys must contain 32 bytes.');
    }
    if (this.nonceBytes.length != 24 || this.macBytes.length != 16) {
      throw ArgumentError('Epoch package cipher metadata is malformed.');
    }
    if (this.cipherTextBytes.length != 32) {
      throw ArgumentError('Encrypted room epoch key must contain 32 bytes.');
    }
    if (this.signatureBytes.length != 64) {
      throw ArgumentError('Epoch package signature must contain 64 bytes.');
    }
  }

  final String roomId;
  final String roomName;
  final int epoch;
  final String keyId;
  final String memberDeviceId;
  final String memberAgreementKeyId;
  final String issuedByDeviceId;
  final Uint8List issuerPublicKeyBytes;
  final Uint8List ephemeralPublicKeyBytes;
  final Uint8List nonceBytes;
  final Uint8List macBytes;
  final Uint8List cipherTextBytes;
  final Uint8List signatureBytes;

  Map<String, Object> get signedFields => <String, Object>{
        'cipherText': base64UrlEncode(cipherTextBytes),
        'ephemeralPublicKey': base64UrlEncode(ephemeralPublicKeyBytes),
        'epoch': epoch,
        'issuedByDeviceId': issuedByDeviceId,
        'issuerPublicKey': base64UrlEncode(issuerPublicKeyBytes),
        'keyId': keyId,
        'mac': base64UrlEncode(macBytes),
        'memberAgreementKeyId': memberAgreementKeyId,
        'memberDeviceId': memberDeviceId,
        'nonce': base64UrlEncode(nonceBytes),
        'roomId': roomId,
        'roomName': roomName,
        'version': 1,
      };

  Map<String, Object> toJson() => <String, Object>{
        ...signedFields,
        'signature': base64UrlEncode(signatureBytes),
      };
}

class RoomEpochKeyPackageCodec {
  RoomEpochKeyPackageCodec({
    X25519? keyExchange,
    Xchacha20? cipher,
    Hkdf? kdf,
    Ed25519? signatureAlgorithm,
    HashAlgorithm? hashAlgorithm,
  })  : _keyExchange = keyExchange ?? X25519(),
        _cipher = cipher ?? Xchacha20.poly1305Aead(),
        _kdf = kdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
        _signatureAlgorithm = signatureAlgorithm ?? Ed25519(),
        _hashAlgorithm = hashAlgorithm ?? Sha256();

  static const String _prefix = 'MTK1';
  final X25519 _keyExchange;
  final Xchacha20 _cipher;
  final Hkdf _kdf;
  final Ed25519 _signatureAlgorithm;
  final HashAlgorithm _hashAlgorithm;

  Future<RoomEpochKeyPackage> issue({
    required SecureRoom room,
    required RoomMembership membership,
    required DeviceIdentity issuer,
  }) async {
    if (membership.roomId != room.id || membership.epoch != room.epoch) {
      throw ArgumentError('Membership must belong to the current room epoch.');
    }
    if (!membership.supportsEpochKeyUpdates ||
        membership.memberAgreementPublicKeyBytes == null ||
        membership.memberAgreementKeyId == null) {
      throw StateError('Member must have a signed X25519 agreement key.');
    }
    if (membership.issuedByDeviceId != issuer.deviceId ||
        !_constantTimeEquals(
          membership.issuerPublicKeyBytes,
          issuer.publicKeyBytes,
        )) {
      throw StateError('Only the membership issuer can package this room epoch.');
    }

    final ephemeral = await _keyExchange.newKeyPair();
    final ephemeralPublic = await ephemeral.extractPublicKey();
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        membership.memberAgreementPublicKeyBytes!,
        type: KeyPairType.x25519,
      ),
    );
    final wrappingKey = await _deriveWrappingKey(
      sharedSecret: sharedSecret,
      roomId: room.id,
      epoch: room.epoch,
      memberDeviceId: membership.memberDeviceId,
      memberAgreementKeyId: membership.memberAgreementKeyId!,
    );
    final aad = _associatedData(
      roomId: room.id,
      epoch: room.epoch,
      keyId: room.keyId,
      memberDeviceId: membership.memberDeviceId,
      memberAgreementKeyId: membership.memberAgreementKeyId!,
      issuedByDeviceId: issuer.deviceId,
    );
    final box = await _cipher.encrypt(
      room.keyBytes,
      secretKey: wrappingKey,
      aad: aad,
    );
    final unsigned = <String, Object>{
      'cipherText': base64UrlEncode(box.cipherText),
      'ephemeralPublicKey': base64UrlEncode(ephemeralPublic.bytes),
      'epoch': room.epoch,
      'issuedByDeviceId': issuer.deviceId,
      'issuerPublicKey': base64UrlEncode(issuer.publicKeyBytes),
      'keyId': room.keyId,
      'mac': base64UrlEncode(box.mac.bytes),
      'memberAgreementKeyId': membership.memberAgreementKeyId!,
      'memberDeviceId': membership.memberDeviceId,
      'nonce': base64UrlEncode(box.nonce),
      'roomId': room.id,
      'roomName': room.name,
      'version': 1,
    };
    final signature = await _signatureAlgorithm.sign(
      _canonicalBytes(unsigned),
      keyPair: SimpleKeyPairData(
        issuer.privateKeyBytes,
        publicKey: SimplePublicKey(
          issuer.publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
        type: KeyPairType.ed25519,
      ),
    );
    return RoomEpochKeyPackage(
      roomId: room.id,
      roomName: room.name,
      epoch: room.epoch,
      keyId: room.keyId,
      memberDeviceId: membership.memberDeviceId,
      memberAgreementKeyId: membership.memberAgreementKeyId!,
      issuedByDeviceId: issuer.deviceId,
      issuerPublicKeyBytes: issuer.publicKeyBytes,
      ephemeralPublicKeyBytes: Uint8List.fromList(ephemeralPublic.bytes),
      nonceBytes: Uint8List.fromList(box.nonce),
      macBytes: Uint8List.fromList(box.mac.bytes),
      cipherTextBytes: Uint8List.fromList(box.cipherText),
      signatureBytes: Uint8List.fromList(signature.bytes),
    );
  }

  Future<Uint8List> open({
    required RoomEpochKeyPackage package,
    required DeviceAgreementIdentity recipient,
  }) async {
    if (package.memberDeviceId != recipient.deviceId ||
        package.memberAgreementKeyId != recipient.keyId) {
      throw const FormatException('Room key package belongs to another device.');
    }
    if (!await verify(package)) {
      throw const FormatException('Room key package signature is invalid.');
    }
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: SimpleKeyPairData(
        recipient.privateKeyBytes,
        publicKey: SimplePublicKey(
          recipient.publicKeyBytes,
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      ),
      remotePublicKey: SimplePublicKey(
        package.ephemeralPublicKeyBytes,
        type: KeyPairType.x25519,
      ),
    );
    final wrappingKey = await _deriveWrappingKey(
      sharedSecret: sharedSecret,
      roomId: package.roomId,
      epoch: package.epoch,
      memberDeviceId: package.memberDeviceId,
      memberAgreementKeyId: package.memberAgreementKeyId,
    );
    try {
      final keyBytes = await _cipher.decrypt(
        SecretBox(
          package.cipherTextBytes,
          nonce: package.nonceBytes,
          mac: Mac(package.macBytes),
        ),
        secretKey: wrappingKey,
        aad: _associatedData(
          roomId: package.roomId,
          epoch: package.epoch,
          keyId: package.keyId,
          memberDeviceId: package.memberDeviceId,
          memberAgreementKeyId: package.memberAgreementKeyId,
          issuedByDeviceId: package.issuedByDeviceId,
        ),
      );
      if (keyBytes.length != 32 ||
          await _deriveRoomKeyId(keyBytes) != package.keyId) {
        throw const FormatException('Room key package contains invalid key material.');
      }
      return Uint8List.fromList(keyBytes);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Room key package authentication failed.');
    }
  }

  Future<bool> verify(RoomEpochKeyPackage package) {
    return _signatureAlgorithm.verify(
      _canonicalBytes(package.signedFields),
      signature: Signature(
        package.signatureBytes,
        publicKey: SimplePublicKey(
          package.issuerPublicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }

  String encode(RoomEpochKeyPackage package) {
    final payload = base64UrlEncode(utf8.encode(jsonEncode(package.toJson())))
        .replaceAll('=', '');
    return '$_prefix.$payload';
  }

  RoomEpochKeyPackage decode(String rawCode) {
    final code = rawCode.trim();
    final parts = code.split('.');
    if (parts.length != 2 || parts[0] != _prefix) {
      throw const FormatException('Room key package has an invalid format.');
    }
    try {
      final raw = jsonDecode(utf8.decode(_decodeBase64Url(parts[1])));
      if (raw is! Map<String, dynamic> || raw['version'] != 1) {
        throw const FormatException('Unsupported room key package version.');
      }
      return RoomEpochKeyPackage(
        roomId: raw['roomId'] as String,
        roomName: raw['roomName'] as String,
        epoch: raw['epoch'] as int,
        keyId: raw['keyId'] as String,
        memberDeviceId: raw['memberDeviceId'] as String,
        memberAgreementKeyId: raw['memberAgreementKeyId'] as String,
        issuedByDeviceId: raw['issuedByDeviceId'] as String,
        issuerPublicKeyBytes: Uint8List.fromList(
          base64Url.decode(raw['issuerPublicKey'] as String),
        ),
        ephemeralPublicKeyBytes: Uint8List.fromList(
          base64Url.decode(raw['ephemeralPublicKey'] as String),
        ),
        nonceBytes: Uint8List.fromList(base64Url.decode(raw['nonce'] as String)),
        macBytes: Uint8List.fromList(base64Url.decode(raw['mac'] as String)),
        cipherTextBytes: Uint8List.fromList(
          base64Url.decode(raw['cipherText'] as String),
        ),
        signatureBytes: Uint8List.fromList(
          base64Url.decode(raw['signature'] as String),
        ),
      );
    } on Object catch (error) {
      throw FormatException('Room key package is malformed: $error');
    }
  }

  Future<SecretKey> _deriveWrappingKey({
    required SecretKey sharedSecret,
    required String roomId,
    required int epoch,
    required String memberDeviceId,
    required String memberAgreementKeyId,
  }) async {
    final salt = (await _hashAlgorithm.hash(
      utf8.encode('meshtalk-room-epoch-salt-v1|$roomId|$epoch'),
    ))
        .bytes;
    return _kdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode(
        'meshtalk-room-epoch-wrap-v1|$memberDeviceId|$memberAgreementKeyId',
      ),
    );
  }

  Uint8List _associatedData({
    required String roomId,
    required int epoch,
    required String keyId,
    required String memberDeviceId,
    required String memberAgreementKeyId,
    required String issuedByDeviceId,
  }) {
    return Uint8List.fromList(
      utf8.encode(
        'meshtalk-room-epoch-aad-v1|$roomId|$epoch|$keyId|'
        '$memberDeviceId|$memberAgreementKeyId|$issuedByDeviceId',
      ),
    );
  }

  Future<String> _deriveRoomKeyId(List<int> keyBytes) async {
    final digest = await _hashAlgorithm.hash(keyBytes);
    return base64UrlEncode(digest.bytes.take(8).toList()).replaceAll('=', '');
  }

  Uint8List _canonicalBytes(Map<String, Object> fields) {
    final keys = fields.keys.toList(growable: false)..sort();
    final canonical = <String, Object>{
      for (final key in keys) key: fields[key]!,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(canonical)));
  }

  List<int> _decodeBase64Url(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    return base64Url.decode('$value$padding');
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
