import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';

enum MessageProtectionStatus {
  endToEndEncrypted,
  legacyUnencrypted,
  unableToDecrypt,
}

enum MessageProtectionFailure {
  malformed,
  keyMismatch,
  authenticationFailed,
}

class MessageProtectionException implements Exception {
  const MessageProtectionException(this.failure, this.message);

  final MessageProtectionFailure failure;
  final String message;

  @override
  String toString() => 'MessageProtectionException($failure): $message';
}

class UnprotectedMessage {
  UnprotectedMessage({
    required Uint8List clearText,
    required this.status,
  }) : clearText = Uint8List.fromList(clearText);

  final Uint8List clearText;
  final MessageProtectionStatus status;
}

class MessageProtector {
  MessageProtector({Xchacha20? algorithm})
      : _algorithm = algorithm ?? Xchacha20.poly1305Aead();

  static const List<int> _magic = <int>[0x4d, 0x54, 0x45, 0x31];
  static const int _version = 1;
  static const int _algorithmId = 1;
  static const int _keyIdLength = 8;
  static const int _nonceLength = 24;
  static const int _macLength = 16;
  static const int headerLength =
      4 + 1 + 1 + _keyIdLength + _nonceLength + _macLength;

  final Xchacha20 _algorithm;

  bool isProtectedPayload(List<int> payload) {
    if (payload.length < headerLength) {
      return false;
    }
    for (var index = 0; index < _magic.length; index += 1) {
      if (payload[index] != _magic[index]) {
        return false;
      }
    }
    return true;
  }

  Future<MessageEnvelope> protect({
    required MessageEnvelope envelope,
    required Uint8List clearText,
    required SecureRoom room,
  }) async {
    if (envelope.roomId != room.id) {
      throw ArgumentError.value(
        envelope.roomId,
        'envelope.roomId',
        'Envelope room ID must match the active secure room.',
      );
    }

    final keyIdBytes = _decodeBase64Url(room.keyId);
    if (keyIdBytes.length != _keyIdLength) {
      throw StateError('Secure room key ID is malformed.');
    }
    final secretBox = await _algorithm.encrypt(
      clearText,
      secretKey: SecretKey(room.keyBytes),
      aad: _associatedData(envelope),
    );
    if (secretBox.nonce.length != _nonceLength ||
        secretBox.mac.bytes.length != _macLength) {
      throw StateError('Authenticated cipher returned an unexpected frame.');
    }

    final bytes = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(_version)
      ..addByte(_algorithmId)
      ..add(keyIdBytes)
      ..add(secretBox.nonce)
      ..add(secretBox.mac.bytes)
      ..add(secretBox.cipherText);
    return envelope.copyWith(payload: bytes.takeBytes());
  }

  Future<UnprotectedMessage> unprotect({
    required MessageEnvelope envelope,
    required SecureRoom room,
    bool allowLegacy = false,
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
    if (payload[4] != _version || payload[5] != _algorithmId) {
      throw const MessageProtectionException(
        MessageProtectionFailure.malformed,
        'Encrypted payload uses an unsupported version or algorithm.',
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
        aad: _associatedData(envelope),
      );
      return UnprotectedMessage(
        clearText: Uint8List.fromList(clearText),
        status: MessageProtectionStatus.endToEndEncrypted,
      );
    } on SecretBoxAuthenticationError {
      throw const MessageProtectionException(
        MessageProtectionFailure.authenticationFailed,
        'Encrypted message authentication failed.',
      );
    }
  }

  Uint8List _associatedData(MessageEnvelope envelope) {
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
    try {
      return base64Url.decode('$value$padding');
    } on FormatException {
      throw StateError('Secure room key ID is malformed.');
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
