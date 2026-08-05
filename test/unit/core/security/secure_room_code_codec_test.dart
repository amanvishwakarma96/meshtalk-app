import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';

void main() {
  late SecureRoomCodeCodec codec;

  setUp(() {
    codec = SecureRoomCodeCodec();
  });

  test('round-trips room identity and key material', () async {
    final key = Uint8List.fromList(
      List<int>.generate(32, (index) => (index * 7) % 256),
    );
    final room = SecureRoom(
      id: 'secureRoomIdentifier1234',
      name: 'Family mesh',
      keyId: await codec.deriveKeyId(key),
      keyBytes: key,
      createdAtUtc: DateTime.utc(2026, 8, 5),
    );

    final code = await codec.encode(room);
    final decoded = await codec.decode(code);

    expect(code, startsWith('MT1.'));
    expect(decoded.id, room.id);
    expect(decoded.name, room.name);
    expect(decoded.keyId, room.keyId);
    expect(decoded.keyBytes, room.keyBytes);
  });

  test('rejects a checksum-tampered room code', () async {
    final room = await _room(codec);
    final code = await codec.encode(room);
    final replacement = code.endsWith('A') ? 'B' : 'A';
    final tampered = '${code.substring(0, code.length - 1)}$replacement';

    await expectLater(
      codec.decode(tampered),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('checksum'),
        ),
      ),
    );
  });

  test('rejects malformed and truncated codes', () async {
    await expectLater(
      codec.decode('MT1.not-enough-fields'),
      throwsFormatException,
    );
    await expectLater(codec.decode('not-a-room-code'), throwsFormatException);
  });

  test('normalizes room names before creation', () {
    expect(codec.normalizeRoomName('  Family   Group  '), 'Family Group');
    expect(
      () => codec.normalizeRoomName('x'),
      throwsFormatException,
    );
  });
}

Future<SecureRoom> _room(SecureRoomCodeCodec codec) async {
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
  return SecureRoom(
    id: 'secureRoomIdentifier1234',
    name: 'Family mesh',
    keyId: await codec.deriveKeyId(key),
    keyBytes: key,
    createdAtUtc: DateTime.utc(2026, 8, 5),
  );
}
