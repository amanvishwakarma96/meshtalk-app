import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

void main() {
  test('creates and reloads one stable encrypted room', () async {
    final values = MemorySecureValueStore();
    final firstStore = SecureRoomStore(
      values: values,
      random: Random(7),
      nowUtc: () => DateTime.utc(2026, 8, 5),
    );

    final first = await firstStore.loadOrCreate();
    final secondStore = SecureRoomStore(
      values: values,
      random: Random(999),
      nowUtc: () => DateTime.utc(2026, 8, 6),
    );
    final second = await secondStore.loadOrCreate();

    expect(second.id, first.id);
    expect(second.keyId, first.keyId);
    expect(second.keyBytes, first.keyBytes);
    expect((await secondStore.listRooms()).length, 1);
  });

  test('exports and imports identical room key material', () async {
    final creator = SecureRoomStore(
      values: MemorySecureValueStore(),
      random: Random(11),
      nowUtc: () => DateTime.utc(2026, 8, 5),
    );
    final created = await creator.createRoom('Shared family room');
    final code = await creator.exportRoomCode(created.id);

    final joiner = SecureRoomStore(
      values: MemorySecureValueStore(),
      random: Random(12),
      nowUtc: () => DateTime.utc(2026, 8, 6),
    );
    final joined = await joiner.importRoomCode(code);

    expect(joined.id, created.id);
    expect(joined.name, created.name);
    expect(joined.keyId, created.keyId);
    expect(joined.keyBytes, created.keyBytes);
    expect((await joiner.loadActive())?.id, created.id);
  });

  test('re-importing the same room activates without duplicating it',
      () async {
    final store = SecureRoomStore(
      values: MemorySecureValueStore(),
      random: Random(15),
      nowUtc: () => DateTime.utc(2026, 8, 5),
    );
    final room = await store.createRoom('Reusable room');
    await store.createRoom('Another room');
    final code = await store.exportRoomCode(room.id);

    final imported = await store.importRoomCode(code);

    expect(imported.id, room.id);
    expect((await store.loadActive())?.id, room.id);
    expect((await store.listRooms()).length, 2);
  });

  test('rejects an existing room ID with different key material', () async {
    final codec = SecureRoomCodeCodec();
    final store = SecureRoomStore(
      values: MemorySecureValueStore(),
      random: Random(21),
      nowUtc: () => DateTime.utc(2026, 8, 5),
    );
    final original = await store.createRoom('Collision room');
    final replacementKey = Uint8List.fromList(
      List<int>.generate(32, (index) => 255 - index),
    );
    final malicious = SecureRoom(
      id: original.id,
      name: original.name,
      keyId: await codec.deriveKeyId(replacementKey),
      keyBytes: replacementKey,
      createdAtUtc: DateTime.utc(2026, 8, 5),
    );

    await expectLater(
      store.importRoomCode(await codec.encode(malicious)),
      throwsFormatException,
    );
  });

  test('surfaces corrupt secure storage instead of replacing keys', () async {
    final values = MemorySecureValueStore()
      ..values['meshtalk.secure-rooms.v1'] = '{broken-json';
    final store = SecureRoomStore(values: values, random: Random(1));

    await expectLater(
      store.loadOrCreate(),
      throwsA(isA<StateError>()),
    );
    expect(values.values['meshtalk.secure-rooms.v1'], '{broken-json');
  });
}

class MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
