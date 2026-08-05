import 'dart:typed_data';

class SecureRoom {
  SecureRoom({
    required this.id,
    required this.name,
    required this.keyId,
    required Uint8List keyBytes,
    required this.createdAtUtc,
  }) : keyBytes = Uint8List.fromList(keyBytes) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid secure room identifier.');
    }
    if (name.trim().length < 2 || name.trim().length > 32) {
      throw ArgumentError.value(
        name,
        'name',
        'Secure room names must contain 2-32 characters.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{8,24}$').hasMatch(keyId)) {
      throw ArgumentError.value(keyId, 'keyId', 'Invalid secure room key ID.');
    }
    if (this.keyBytes.length != 32) {
      throw ArgumentError.value(
        this.keyBytes.length,
        'keyBytes',
        'Secure room keys must contain exactly 32 bytes.',
      );
    }
  }

  final String id;
  final String name;
  final String keyId;
  final Uint8List keyBytes;
  final DateTime createdAtUtc;

  SecureRoomSummary get summary => SecureRoomSummary(
        id: id,
        name: name,
        keyId: keyId,
        createdAtUtc: createdAtUtc,
      );
}

class SecureRoomSummary {
  const SecureRoomSummary({
    required this.id,
    required this.name,
    required this.keyId,
    required this.createdAtUtc,
  });

  final String id;
  final String name;
  final String keyId;
  final DateTime createdAtUtc;

  String get fingerprint {
    final normalized = keyId.toUpperCase();
    if (normalized.length <= 8) {
      return normalized;
    }
    return '${normalized.substring(0, 4)}-${normalized.substring(4, 8)}';
  }
}
