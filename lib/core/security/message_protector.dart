import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';

enum MessageProtectionStatus {
  endToEndEncrypted,
  encryptedLegacyIdentity,
  legacyUnencrypted,
  unableToDecrypt,
}

enum MessageProtectionFailure {
  malformed,
  keyMismatch,
  authenticationFailed,
  identityMalformed,
  signatureInvalid,
  unsignedIdentity,
}

class MessageProtectionException implements Exception {
  const MessageProtectionException(this.failure, this.message);

  final MessageProtectionFailure failure;
  final String message;

  @override
  String toString() => 'MessageProtectionException($failure): $message';
}

class VerifiedSenderIdentity {
  VerifiedSenderIdentity({
    required this.keyId,
    required Uint8List publicKeyBytes,
  }) : publicKeyBytes = Uint8List.fromList(publicKeyBytes);

  final String keyId;
  final Uint8List publicKeyBytes;

  String get fingerprint => identityFingerprint(keyId);
}

class UnprotectedMessage {
  UnprotectedMessage({
    required Uint8List clearText,
    required this.status,
    this.senderIdentity,
  }) : clearText = Uint8List.fromList(clearText);

  final Uint8List clearText;
  final MessageProtectionStatus status;
  final VerifiedSenderIdentity? senderIdentity;
}

class MessageProtector {
  MessageProtector({
    Xchacha20? algorithm,
    Ed25519? signatureAlgorithm,
    HashAlgorithm? hashAlgorithm,
  })  : _algorithm = algorithm ?? Xchacha20.poly1305Aead(),
        _signatureAlgorithm = signatureAlgorithm ?? Ed25519(),
        _hashAlgorithm = hashAlgorithm ?? Sha256();

  static const List<int> _magic = <int>[0x4d, 0x54, 0x45, 0x31];
  static const int _legacyVersion = 1;
  static const int _signedVersion = 2;
  static const int _algorithmId = 1;
  static const int _keyIdLength = 8;
  static const int _identityKeyIdLength = 8;
  static const int _publicKeyLength = 32;
  static const int _nonceLength = 24;
  static const int _macLength = 16;
  static const int _signatureLength = 64;
  static const int legacyHeaderLength =
      4 + 1 + 1 + _keyIdLength + _nonceLength + _macLength;
  static const int signedHeaderLength = 4 +
      1 +
      1 +
      _keyIdLength +
      _identityKeyIdLength +
      _publicKeyLength +
      _nonceLength +
      _macLength +
      _signatureLength;

  final Xchacha20 _algorithm;
  final Ed25519 _signatureAlgorithm;
  final HashAlgorithm _hashAlgorithm;

  bool isProtectedPayload(List<int> payload) {
    if (payload.length < legacyHeaderLength) {
      return false;
    }
    for (var index = 0; index < _magic.length; index += 1) {
      if (payload[index] != _magic[index]) {
        return false;
      }
    }
    return true;
  }

  bool isSignedProtectedPayload(List<int> payload) {
    return isProtectedPayload(payload) &&
        payload.length >= signedHeaderLength &&
        payload[4] == _signedVersion;
  }

  Future<MessageEnvelope> protect({
    required MessageEnvelope envelope,
    required Uint8List clearText,
    required SecureRoom room,
    required DeviceIdentity identity,
  }) async {
    if (envelope.roomId != room.id) {
      throw ArgumentError.value(
        envelope.roomId,
        'envelope.roomId',
        'Envelope room ID must match the active secure room.',
      );
    }
    if (envelope.senderId != identity.deviceId) {
      throw ArgumentError.value(
        envelope.senderId,
        'envelope.senderId',
        'Envelope sender ID must match the signing identity.',
      );
    }

    final roomKeyIdBytes = _decodeBase64Url(room.keyId);
    final identityKeyIdBytes = _decodeBase64Url(identity.keyId);
    if (roomKeyIdBytes.length != _keyIdLength ||
        identityKeyIdBytes.length != _identityKeyIdLength) {
      throw StateError('Room or identity key ID is malformed.');
    }

    final aad = _associatedDataV2(
      envelope,
      identityKeyIdBytes,
      identity.publicKeyBytes,
    );
    final secretBox = await _algorithm.encrypt(
      clearText,
      secretKey: SecretKey(room.keyBytes),
      aad: aad,
    );
    if (secretBox.nonce.length != _nonceLength ||
        secretBox.mac.bytes.length != _macLength) {
      throw StateError('Authenticated cipher returned an unexpected frame.');
    }

    final unsignedHeader = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_signedVersion)
      ..addByte(_algorithmId)
      ..add(roomKeyIdBytes)
      ..add(identityKeyIdBytes)
      ..add(identity.publicKeyBytes)
      ..add(secretBox.nonce)
      ..add(secretBox.mac.bytes);
    final unsignedHeaderBytes = unsignedHeader.takeBytes();
    final signatureInput = _signatureInput(
      aad: aad,
      unsignedHeader: unsignedHeaderBytes,
      cipherText: secretBox.cipherText,
    );
    final keyPair = SimpleKeyPairData(
      identity.privateKeyBytes,
      publicKey: SimplePublicKey(
        identity.publicKeyBytes,
        type: KeyPairType.ed25519,
      ),
      type: KeyPairType.ed25519,
    );
    final signature = await _signatureAlgorithm.sign(
      signatureInput,
      keyPair: keyPair,
    );
    if (signature.bytes.length != _signatureLength) {
      throw StateError('Ed25519 returned an unexpected signature length.');
    }

    final bytes = BytesBuilder(copy: false)
      ..add(unsignedHeaderBytes)
      ..add(signature.bytes)
      ..add(secretBox.cipherText);
    return envelope.copyWith(payload: bytes.takeBytes());
  }

  Future<UnprotectedMessage> unprotect({
    required MessageEnvelope envelope,
    required SecureRoom room,
    bool allowLegacy = false,
    bool allowLegacyIdentity = false,
  }) async {
    final payload = envelope.payload;
    if (!isProtectedPayload(payload)) {
      if (allowLegacy) {
        return UnprotectedMessage(
          clearText: payload,
          status: MessageProtectionStatus.legacyUnencrypted,
        );
      }
      throw const MessageProtectionException(
        MessageProtectionFailure.malformed,
        'Unauthenticated legacy payload rejected in a secure room.',
      );
    }

    return switch (payload[4]) {
      _legacyVersion => _unprotectLegacyIdentity(
          envelope: envelope,
          room: room,
          allowLegacyIdentity: allowLegacyIdentity,
        ),
      _signedVersion => _unprotectSigned(
          envelope: envelope,
          room: room,
        ),
      _ => throw const MessageProtectionException(
          MessageProtectionFailure.malformed,
          'Encrypted payload uses an unsupported protocol version.',
        ),
    };
  }

  Future<UnprotectedMessage> _unprotectSigned({
    required MessageEnvelope envelope,
    required SecureRoom room,
  }) async {
    final payload = envelope.payload;
    if (payload.length < signedHeaderLength || payload[5] != _algorithmId) {
      throw const MessageProtectionException(
        MessageProtectionFailure.malformed,
        'Signed encrypted payload is truncated or uses an unsupported algorithm.',
      );
    }

    final roomKeyIdStart = 6;
    final identityKeyIdStart = roomKeyIdStart + _keyIdLength;
    final publicKeyStart = identityKeyIdStart + _identityKeyIdLength;
    final nonceStart = publicKeyStart + _publicKeyLength;
    final macStart = nonceStart + _nonceLength;
    final signatureStart = macStart + _macLength;
    final cipherTextStart = signatureStart + _signatureLength;

    final receivedRoomKeyId = payload.sublist(
      roomKeyIdStart,
      identityKeyIdStart,
    );
    final expectedRoomKeyId = _decodeBase64Url(room.keyId);
    if (!_constantTimeEquals(receivedRoomKeyId, expectedRoomKeyId)) {
      throw const MessageProtectionException(
        MessageProtectionFailure.keyMismatch,
        'Encrypted message belongs to a different room key.',
      );
    }

    final identityKeyIdBytes = payload.sublist(
      identityKeyIdStart,
      publicKeyStart,
    );
    final publicKeyBytes = payload.sublist(publicKeyStart, nonceStart);
    final derivedIdentityKeyId = await _deriveIdentityKeyId(publicKeyBytes);
    if (!_constantTimeEquals(identityKeyIdBytes, derivedIdentityKeyId)) {
      throw const MessageProtectionException(
        MessageProtectionFailure.identityMalformed,
        'Sender identity key ID does not match its public key.',
      );
    }

    final aad = _associatedDataV2(
      envelope,
      identityKeyIdBytes,
      publicKeyBytes,
    );
    final unsignedHeader = payload.sublist(0, signatureStart);
    final cipherText = payload.sublist(cipherTextStart);
    final signature = Signature(
      payload.sublist(signatureStart, cipherTextStart),
      publicKey: SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      ),
    );
    final signatureValid = await _signatureAlgorithm.verify(
      _signatureInput(
        aad: aad,
        unsignedHeader: unsignedHeader,
        cipherText: cipherText,
      ),
      signature: signature,
    );
    if (!signatureValid) {
      throw const MessageProtectionException(
        MessageProtectionFailure.signatureInvalid,
        'Sender identity signature is invalid.',
      );
    }

    final secretBox = SecretBox(
      cipherText,
      nonce: payload.sublist(nonceStart, macStart),
      mac: Mac(payload.sublist(macStart, signatureStart)),
    );
    try {
      final clearText = await _algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(room.keyBytes),
        aad: aad,
      );
      return UnprotectedMessage(
        clearText: Uint8List.fromList(clearText),
        status: MessageProtectionStatus.endToEndEncrypted,
        senderIdentity: VerifiedSenderIdentity(
          keyId: _base64UrlWithoutPadding(identityKeyIdBytes),
          publicKeyBytes: Uint8List.fromList(publicKeyBytes),
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const MessageProtectionException(
        MessageProtectionFailure.authenticationFailed,
        'Encrypted message authentication failed.',
      );
    }
  }

  Future<UnprotectedMessage> _unprotectLegacyIdentity({
    required MessageEnvelope envelope,
    required SecureRoom room,
    required bool allowLegacyIdentity,
  }) async {
    if (!allowLegacyIdentity) {
      throw const MessageProtectionException(
        MessageProtectionFailure.unsignedIdentity,
        'Unsigned version-1 encrypted payload rejected from the network.',
      );
    }
    final payload = envelope.payload;
    if (payload.length < legacyHeaderLength || payload[5] != _algorithmId) {
      throw const MessageProtectionException(
        MessageProtectionFailure.malformed,
        'Legacy encrypted payload is truncated or unsupported.',
      );
    }

    final keyIdStart = 6;
    final nonceStart = keyIdStart + _keyIdLength;
    final macStart = nonceStart + _nonceLength;
    final cipherTextStart = macStart + _macLength;
    final receivedKeyId = payload.sublist(keyIdStart, nonceStart);
    final expectedKeyId = _decodeBase64Url(room.keyId);
    if (!_constantTimeEquals(receivedKeyId, expectedKeyId)) {
      throw const MessageProtectionException(
        MessageProtectionFailure.keyMismatch,
        'Encrypted message belongs to a different room key.',
      );
    }

    final secretBox = SecretBox(
      payload.sublist(cipherTextStart),
      nonce: payload.sublist(nonceStart, macStart),
      mac: Mac(payload.sublist(macStart, cipherTextStart)),
    );
    try {
      final clearText = await _algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(room.keyBytes),
        aad: _associatedDataV1(envelope),
      );
      return UnprotectedMessage(
        clearText: Uint8List.fromList(clearText),
        status: MessageProtectionStatus.encryptedLegacyIdentity,
      );
    } on SecretBoxAuthenticationError {
      throw const MessageProtectionException(
        MessageProtectionFailure.authenticationFailed,
        'Legacy encrypted message authentication failed.',
      );
    }
  }

  Uint8List _associatedDataV1(MessageEnvelope envelope) {
    final timestamp = envelope.timestampUtc.toUtc().microsecondsSinceEpoch;
    return Uint8List.fromList(
      utf8.encode(
        'meshtalk-e2ee-v1|${_field(envelope.id)}|'
        '${_field(envelope.senderId)}|${_field(envelope.roomId)}|$timestamp',
      ),
    );
  }

  Uint8List _associatedDataV2(
    MessageEnvelope envelope,
    List<int> identityKeyId,
    List<int> publicKey,
  ) {
    final timestamp = envelope.timestampUtc.toUtc().microsecondsSinceEpoch;
    return Uint8List.fromList(
      utf8.encode(
        'meshtalk-e2ee-v2|${_field(envelope.id)}|'
        '${_field(envelope.senderId)}|${_field(envelope.roomId)}|$timestamp|'
        '${_field(_base64UrlWithoutPadding(identityKeyId))}|'
        '${_field(_base64UrlWithoutPadding(publicKey))}',
      ),
    );
  }

  Uint8List _signatureInput({
    required Uint8List aad,
    required List<int> unsignedHeader,
    required List<int> cipherText,
  }) {
    return (BytesBuilder(copy: false)
          ..add(utf8.encode('meshtalk-ed25519-signature-v1'))
          ..add(aad)
          ..add(unsignedHeader)
          ..add(cipherText))
        .takeBytes();
  }

  Future<List<int>> _deriveIdentityKeyId(List<int> publicKey) async {
    final digest = await _hashAlgorithm.hash(publicKey);
    return digest.bytes.take(_identityKeyIdLength).toList(growable: false);
  }

  String _field(String value) => '${utf8.encode(value).length}:$value';

  List<int> _decodeBase64Url(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    try {
      return base64Url.decode('$value$padding');
    } on FormatException {
      throw StateError('Room or identity key ID is malformed.');
    }
  }

  String _base64UrlWithoutPadding(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
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
