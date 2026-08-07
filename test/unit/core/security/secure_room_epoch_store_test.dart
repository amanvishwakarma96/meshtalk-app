import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

void main() {
  test('migrates version-1 storage to epoch one and retains old key', () async {
    final values = _MemorySecureValueStore();
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
    final keyId = await SecureRoomCodeCodec().deriveKeyId(key);
    values.values['meshtalk.secure-rooms.v1'] = jsonEncode(<String, Object>{
      'version': 1,
      'activeRoomId': 'secureRoomIdentifier1234',
      'rooms': <Object>[
        <String, Object>{
          'id': 'secureRoomIdentifier1234',
          'name': 'Legacy room',
          'keyId': keyId,
          'key': base64UrlEncode(key).replaceAll('=', ''),
          'createdAtUtc': DateTime.utc(2026, 8, 1).toIso8601String(),
        },
      ],
    });
    final store = SecureRoomStore(
      values: values,
      nowUtc: () => DateTime.utc(2026, 8, 7),
    );

    final migrated = await store.loadOrCreate();
    expect(migrated.epoch, 1);
    expect(migrated.historicalKeys, isEmpty);

    final rotated = await store.rotateRoomKey(migrated.id);
    expect(rotated.epoch, 2);
    expect(rotated.keyId, isNot(migrated.keyId));
    expect(rotated.historicalKeys.single.epoch, 1);
    expect(rotated.historicalKeys.single.keyId, migrated.keyId);

    final oldEpoch = await store.roomForKeyId(rotated.id, migrated.keyId);
    expect(oldEpoch?.epoch, 1);
    expect(oldEpoch?.keyId, migrated.keyId);

    final persisted = jsonDecode(
      values.values['meshtalk.secure-rooms.v1']!,
    ) as Map<String, dynamic>;
    expect(persisted['version'], 2);
  });

  test('MT2 room codes preserve a rotated epoch', () async {
    final values = _MemorySecureValueStore();
    final store = SecureRoomStore(values: values);
    final original = await store.createRoom('Rotated room');
    final rotated = await store.rotateRoomKey(original.id);
    final code = await store.exportRoomCode(rotated.id);

    expect(code, startsWith('MT2.'));
    final decoded = await SecureRoomCodeCodec().decode(code);
    expect(decoded.id, rotated.id);
    expect(decoded.epoch, 2);
    expect(decoded.keyId, rotated.keyId);
    expect(decoded.keyBytes, rotated.keyBytes);
  });

  test('rejects skipped epoch installation', () async {
    final values = _MemorySecureValueStore();
    final store = SecureRoomStore(values: values);
    final room = await store.createRoom('Gap room');
    final key = Uint8List.fromList(
      List<int>.generate(32, (index) => 255 - index),
    );
    final keyId = await SecureRoomCodeCodec().deriveKeyId(key);

    await expectLater(
      store.installEpochKey(
        roomId: room.id,
        roomName: room.name,
        epoch: 3,
        keyId: keyId,
        keyBytes: key,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
