import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/security/secure_room_code_codec.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureRoomStore {
  SecureRoomStore({
    required SecureValueStore values,
    SecureRoomCodeCodec? codeCodec,
    Random? random,
    DateTime Function()? nowUtc,
  })  : _values = values,
        _codeCodec = codeCodec ?? SecureRoomCodeCodec(),
        _random = random ?? Random.secure(),
        _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static const String _storageKey = 'meshtalk.secure-rooms.v1';
  static const int _maximumStoredRooms = 16;

  final SecureValueStore _values;
  final SecureRoomCodeCodec _codeCodec;
  final Random _random;
  final DateTime Function() _nowUtc;

  Future<SecureRoom> loadOrCreate() async {
    final state = await _readState();
    if (state.rooms.isEmpty) {
      return createRoom('My secure room');
    }
    final active = state.roomById(state.activeRoomId);
    if (active == null) {
      throw StateError('Secure room storage has no valid active room.');
    }
    return active;
  }

  Future<SecureRoom?> loadActive() async {
    final state = await _readState();
    if (state.rooms.isEmpty) {
      return null;
    }
    return state.roomById(state.activeRoomId);
  }

  Future<List<SecureRoomSummary>> listRooms() async {
    final state = await _readState();
    final rooms = state.rooms
        .map((room) => room.summary)
        .toList(growable: false)
      ..sort((left, right) => right.createdAtUtc.compareTo(left.createdAtUtc));
    return List<SecureRoomSummary>.unmodifiable(rooms);
  }

  Future<SecureRoom> createRoom(String rawName) async {
    final name = _codeCodec.normalizeRoomName(rawName);
    final state = await _readState();
    if (state.rooms.length >= _maximumStoredRooms) {
      throw StateError(
        'Secure room limit reached. Remove an unused room before creating another.',
      );
    }

    final keyBytes = _randomBytes(32);
    final room = SecureRoom(
      id: _base64UrlWithoutPadding(_randomBytes(16)),
      name: name,
      keyId: await _codeCodec.deriveKeyId(keyBytes),
      keyBytes: keyBytes,
      createdAtUtc: _nowUtc(),
    );
    await _writeState(
      _SecureRoomState(
        activeRoomId: room.id,
        rooms: <SecureRoom>[...state.rooms, room],
      ),
    );
    return room;
  }

  Future<SecureRoom> importRoomCode(String code) async {
    final imported = await _codeCodec.decode(code);
    final state = await _readState();
    final existing = state.roomById(imported.id);
    if (existing != null) {
      if (!_constantTimeEquals(existing.keyBytes, imported.keyBytes)) {
        throw const FormatException(
          'Room ID already exists with different key material.',
        );
      }
      await _writeState(
        _SecureRoomState(
          activeRoomId: existing.id,
          rooms: state.rooms,
        ),
      );
      return existing;
    }
    if (state.rooms.length >= _maximumStoredRooms) {
      throw StateError(
        'Secure room limit reached. Remove an unused room before joining another.',
      );
    }

    final room = SecureRoom(
      id: imported.id,
      name: imported.name,
      keyId: imported.keyId,
      keyBytes: imported.keyBytes,
      createdAtUtc: _nowUtc(),
    );
    await _writeState(
      _SecureRoomState(
        activeRoomId: room.id,
        rooms: <SecureRoom>[...state.rooms, room],
      ),
    );
    return room;
  }

  Future<void> activateRoom(String roomId) async {
    final state = await _readState();
    final room = state.roomById(roomId);
    if (room == null) {
      throw StateError('The selected secure room is no longer available.');
    }
    if (state.activeRoomId == roomId) {
      return;
    }
    await _writeState(
      _SecureRoomState(activeRoomId: roomId, rooms: state.rooms),
    );
  }

  Future<String> exportActiveRoomCode() async {
    final room = await loadActive();
    if (room == null) {
      throw StateError('No secure room is configured.');
    }
    return _codeCodec.encode(room);
  }

  Future<String> exportRoomCode(String roomId) async {
    final state = await _readState();
    final room = state.roomById(roomId);
    if (room == null) {
      throw StateError('The selected secure room is no longer available.');
    }
    return _codeCodec.encode(room);
  }

  Future<_SecureRoomState> _readState() async {
    final encoded = await _values.read(_storageKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return const _SecureRoomState(activeRoomId: null, rooms: <SecureRoom>[]);
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('Unsupported secure room storage version.');
      }
      final activeRoomId = decoded['activeRoomId'];
      final rawRooms = decoded['rooms'];
      if (activeRoomId is! String || rawRooms is! List<dynamic>) {
        throw const FormatException('Secure room storage is malformed.');
      }
      final rooms = rawRooms.map(_roomFromJson).toList(growable: false);
      if (rooms.length > _maximumStoredRooms) {
        throw const FormatException('Secure room storage exceeds its limit.');
      }
      return _SecureRoomState(activeRoomId: activeRoomId, rooms: rooms);
    } on FormatException catch (error) {
      throw StateError('Secure room key storage is corrupt: ${error.message}');
    } on Object catch (error) {
      throw StateError('Secure room key storage is corrupt: $error');
    }
  }

  SecureRoom _roomFromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Secure room entry must be an object.');
    }
    final id = raw['id'];
    final name = raw['name'];
    final keyId = raw['keyId'];
    final key = raw['key'];
    final createdAtUtc = raw['createdAtUtc'];
    if (id is! String ||
        name is! String ||
        keyId is! String ||
        key is! String ||
        createdAtUtc is! String) {
      throw const FormatException('Secure room entry contains invalid fields.');
    }
    return SecureRoom(
      id: id,
      name: name,
      keyId: keyId,
      keyBytes: Uint8List.fromList(_decodeBase64Url(key)),
      createdAtUtc: DateTime.parse(createdAtUtc).toUtc(),
    );
  }

  Future<void> _writeState(_SecureRoomState state) async {
    final encoded = jsonEncode(<String, Object?>{
      'version': 1,
      'activeRoomId': state.activeRoomId,
      'rooms': state.rooms
          .map(
            (room) => <String, Object>{
              'id': room.id,
              'name': room.name,
              'keyId': room.keyId,
              'key': _base64UrlWithoutPadding(room.keyBytes),
              'createdAtUtc': room.createdAtUtc.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
    });
    await _values.write(_storageKey, encoded);
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
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

class _SecureRoomState {
  const _SecureRoomState({required this.activeRoomId, required this.rooms});

  final String? activeRoomId;
  final List<SecureRoom> rooms;

  SecureRoom? roomById(String? roomId) {
    if (roomId == null) {
      return null;
    }
    for (final room in rooms) {
      if (room.id == roomId) {
        return room;
      }
    }
    return null;
  }
}
