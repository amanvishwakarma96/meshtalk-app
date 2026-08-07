import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';

class SecureRoomCodeCodec {
  SecureRoomCodeCodec({HashAlgorithm? hashAlgorithm})
      : _hashAlgorithm = hashAlgorithm ?? Sha256();

  static const String _legacyPrefix = 'MT1';
  static const String _epochPrefix = 'MT2';
  final HashAlgorithm _hashAlgorithm;

  Future<String> encode(SecureRoom room) async {
    final key = _base64UrlWithoutPadding(room.keyBytes);
    final name = _base64UrlWithoutPadding(utf8.encode(room.name.trim()));
    if (room.epoch == 1) {
      final canonical = '$_legacyPrefix|${room.id}|$key|$name';
      final checksum = await _checksum(canonical);
      return '$_legacyPrefix.${room.id}.$key.$name.$checksum';
    }
    final canonical = '$_epochPrefix|${room.id}|${room.epoch}|$key|$name';
    final checksum = await _checksum(canonical);
    return '$_epochPrefix.${room.id}.${room.epoch}.$key.$name.$checksum';
  }

  Future<SecureRoom> decode(String rawCode) async {
    final code = rawCode.trim();
    final parts = code.split('.');
    if (parts.isEmpty) {
      throw const FormatException('Secure room code has an invalid format.');
    }
    return switch (parts[0]) {
      _legacyPrefix => _decodeLegacy(parts),
      _epochPrefix => _decodeEpoch(parts),
      _ =>
        throw const FormatException('Secure room code has an invalid format.'),
    };
  }

  Future<SecureRoom> _decodeLegacy(List<String> parts) async {
    if (parts.length != 5) {
      throw const FormatException('Secure room code has an invalid format.');
    }
    return _decodeParts(
      roomId: parts[1],
      epoch: 1,
      keyText: parts[2],
      nameText: parts[3],
      suppliedChecksum: parts[4],
      canonical: '$_legacyPrefix|${parts[1]}|${parts[2]}|${parts[3]}',
    );
  }

  Future<SecureRoom> _decodeEpoch(List<String> parts) async {
    if (parts.length != 6) {
      throw const FormatException('Secure room code has an invalid format.');
    }
    final epoch = int.tryParse(parts[2]);
    if (epoch == null || epoch < 2) {
      throw const FormatException(
          'Secure room code contains an invalid epoch.');
    }
    return _decodeParts(
      roomId: parts[1],
      epoch: epoch,
      keyText: parts[3],
      nameText: parts[4],
      suppliedChecksum: parts[5],
      canonical: '$_epochPrefix|${parts[1]}|$epoch|${parts[3]}|${parts[4]}',
    );
  }

  Future<SecureRoom> _decodeParts({
    required String roomId,
    required int epoch,
    required String keyText,
    required String nameText,
    required String suppliedChecksum,
    required String canonical,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(roomId)) {
      throw const FormatException(
        'Secure room code contains an invalid room ID.',
      );
    }

    final expectedChecksum = await _checksum(canonical);
    if (!_constantTimeEquals(
      utf8.encode(suppliedChecksum),
      utf8.encode(expectedChecksum),
    )) {
      throw const FormatException('Secure room code checksum does not match.');
    }

    late final Uint8List keyBytes;
    late final String roomName;
    try {
      keyBytes = Uint8List.fromList(_decodeBase64Url(keyText));
      roomName = utf8.decode(_decodeBase64Url(nameText));
    } on FormatException {
      throw const FormatException('Secure room code contains invalid data.');
    }

    if (keyBytes.length != 32) {
      throw const FormatException('Secure room code contains an invalid key.');
    }
    final normalizedName = _normalizeName(roomName);
    final keyId = await deriveKeyId(keyBytes);
    final now = DateTime.now().toUtc();
    return SecureRoom(
      id: roomId,
      name: normalizedName,
      epoch: epoch,
      keyId: keyId,
      keyBytes: keyBytes,
      createdAtUtc: now,
      keyActivatedAtUtc: now,
    );
  }

  Future<String> deriveKeyId(List<int> keyBytes) async {
    if (keyBytes.length != 32) {
      throw ArgumentError.value(
        keyBytes.length,
        'keyBytes',
        'Secure room keys must contain exactly 32 bytes.',
      );
    }
    final digest = await _hashAlgorithm.hash(keyBytes);
    return _base64UrlWithoutPadding(digest.bytes.take(8).toList());
  }

  String normalizeRoomName(String value) => _normalizeName(value);

  Future<String> _checksum(String canonical) async {
    final digest = await _hashAlgorithm.hash(utf8.encode(canonical));
    return _base64UrlWithoutPadding(digest.bytes.take(5).toList());
  }

  String _normalizeName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length < 2 || normalized.length > 32) {
      throw const FormatException(
        'Secure room names must contain 2-32 characters.',
      );
    }
    return normalized;
  }

  String _base64UrlWithoutPadding(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
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
