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
  static const int _maximumHistoricalKeys = 8;

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

  Future<SecureRoom?> loadRoom(String roomId) async {
    return (await _readState()).roomById(roomId);
  }

  Future<SecureRoom?> roomForKeyId(String roomId, String keyId) async {
    final room = await loadRoom(roomId);
    if (room == null || room.keyForId(keyId) == null) {
      return null;
    }
    return room.roomForKeyId(keyId);
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

    final now = _nowUtc();
    final keyBytes = _randomBytes(32);
    final room = SecureRoom(
      id: _base64UrlWithoutPadding(_randomBytes(16)),
      name: name,
      epoch: 1,
      keyId: await _codeCodec.deriveKeyId(keyBytes),
      keyBytes: keyBytes,
      createdAtUtc: now,
      keyActivatedAtUtc: now,
      allowsLocalOwnerBootstrap: true,
    );
    await _writeState(
      _SecureRoomState(
        activeRoomId: room.id,
        rooms: <SecureRoom>[...state.rooms, room],
      ),
    );
    return room;
  }

  Future<SecureRoom> rotateRoomKey(String roomId) async {
    final state = await _readState();
    final room = state.roomById(roomId);
    if (room == null) {
      throw StateError('The selected secure room is no longer available.');
    }
    final keyBytes = _randomBytes(32);
    final rotated = room.rotateTo(
      newKeyId: await _codeCodec.deriveKeyId(keyBytes),
      newKeyBytes: keyBytes,
      activatedAtUtc: _nowUtc(),
      maximumHistoricalKeys: _maximumHistoricalKeys,
    );
    await _writeState(state.replaceRoom(rotated));
    return rotated;
  }

  Future<SecureRoom> installEpochKey({
    required String roomId,
    required String roomName,
    required int epoch,
    required String keyId,
    required Uint8List keyBytes,
    DateTime? activatedAtUtc,
    bool allowsLocalOwnerBootstrap = false,
  }) async {
    if (epoch < 1) {
      throw ArgumentError.value(epoch, 'epoch', 'Room epoch must be positive.');
    }
    final state = await _readState();
    final existing = state.roomById(roomId);
    final activation = (activatedAtUtc ?? _nowUtc()).toUtc();
    if (existing == null) {
      if (state.rooms.length >= _maximumStoredRooms) {
        throw StateError(
          'Secure room limit reached. Remove an unused room before joining another.',
        );
      }
      final room = SecureRoom(
        id: roomId,
        name: _codeCodec.normalizeRoomName(roomName),
        epoch: epoch,
        keyId: keyId,
        keyBytes: keyBytes,
        createdAtUtc: activation,
        keyActivatedAtUtc: activation,
        allowsLocalOwnerBootstrap: allowsLocalOwnerBootstrap,
      );
      await _writeState(
        _SecureRoomState(
          activeRoomId: room.id,
          rooms: <SecureRoom>[...state.rooms, room],
        ),
      );
      return room;
    }

    if (epoch < existing.epoch) {
      final historical =
          existing.keyRing.where((key) => key.epoch == epoch).firstOrNull;
      if (historical == null ||
          historical.keyId != keyId ||
          !_constantTimeEquals(historical.keyBytes, keyBytes)) {
        throw const FormatException(
          'Older room epoch conflicts with local key history.',
        );
      }
      return existing;
    }
    if (epoch == existing.epoch) {
      if (existing.keyId != keyId ||
          !_constantTimeEquals(existing.keyBytes, keyBytes)) {
        throw const FormatException(
          'Current room epoch already exists with different key material.',
        );
      }
      await activateRoom(existing.id);
      return existing;
    }
    if (epoch != existing.epoch + 1) {
      throw StateError(
        'Room key update skipped one or more epochs. Import the missing update first.',
      );
    }

    final rotated = existing.rotateTo(
      newKeyId: keyId,
      newKeyBytes: keyBytes,
      activatedAtUtc: activation,
      maximumHistoricalKeys: _maximumHistoricalKeys,
    );
    await _writeState(
      state.replaceRoom(rotated).copyWith(activeRoomId: rotated.id),
    );
    return rotated;
  }

  Future<SecureRoom> importRoomCode(String code) async {
    final imported = await _codeCodec.decode(code);
    return installEpochKey(
      roomId: imported.id,
      roomName: imported.name,
      epoch: imported.epoch,
      keyId: imported.keyId,
      keyBytes: imported.keyBytes,
      activatedAtUtc: imported.keyActivatedAtUtc,
      allowsLocalOwnerBootstrap: false,
    );
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
    await _writeState(state.copyWith(activeRoomId: roomId));
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
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Secure room storage is malformed.');
      }
      final version = decoded['version'];
      if (version != 1 && version != 2) {
        throw const FormatException('Unsupported secure room storage version.');
      }
      final activeRoomId = decoded['activeRoomId'];
      final rawRooms = decoded['rooms'];
      if (activeRoomId is! String || rawRooms is! List<dynamic>) {
        throw const FormatException('Secure room storage is malformed.');
      }
      final rooms = rawRooms
          .map(version == 1 ? _roomFromJsonV1 : _roomFromJsonV2)
          .toList(growable: false);
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

  SecureRoom _roomFromJsonV1(dynamic raw) {
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
    final created = DateTime.parse(createdAtUtc).toUtc();
    return SecureRoom(
      id: id,
      name: name,
      epoch: 1,
      keyId: keyId,
      keyBytes: Uint8List.fromList(_decodeBase64Url(key)),
      createdAtUtc: created,
      keyActivatedAtUtc: created,
      allowsLocalOwnerBootstrap: true,
    );
  }

  SecureRoom _roomFromJsonV2(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Secure room entry must be an object.');
    }
    final id = raw['id'];
    final name = raw['name'];
    final epoch = raw['epoch'];
    final keyId = raw['keyId'];
    final key = raw['key'];
    final createdAtUtc = raw['createdAtUtc'];
    final keyActivatedAtUtc = raw['keyActivatedAtUtc'];
    final allowsLocalOwnerBootstrap = raw['allowsLocalOwnerBootstrap'];
    final rawHistory = raw['historicalKeys'];
    if (id is! String ||
        name is! String ||
        epoch is! int ||
        keyId is! String ||
        key is! String ||
        createdAtUtc is! String ||
        keyActivatedAtUtc is! String ||
        allowsLocalOwnerBootstrap is! bool ||
        rawHistory is! List<dynamic>) {
      throw const FormatException('Secure room entry contains invalid fields.');
    }
    final history = rawHistory.map(_epochKeyFromJson).toList(growable: false);
    if (history.length > _maximumHistoricalKeys) {
      throw const FormatException('Room key history exceeds its limit.');
    }
    return SecureRoom(
      id: id,
      name: name,
      epoch: epoch,
      keyId: keyId,
      keyBytes: Uint8List.fromList(_decodeBase64Url(key)),
      createdAtUtc: DateTime.parse(createdAtUtc).toUtc(),
      keyActivatedAtUtc: DateTime.parse(keyActivatedAtUtc).toUtc(),
      allowsLocalOwnerBootstrap: allowsLocalOwnerBootstrap,
      historicalKeys: history,
    );
  }

  SecureRoomEpochKey _epochKeyFromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Room epoch key entry must be an object.');
    }
    final epoch = raw['epoch'];
    final keyId = raw['keyId'];
    final key = raw['key'];
    final activatedAtUtc = raw['activatedAtUtc'];
    if (epoch is! int ||
        keyId is! String ||
        key is! String ||
        activatedAtUtc is! String) {
      throw const FormatException('Room epoch key contains invalid fields.');
    }
    return SecureRoomEpochKey(
      epoch: epoch,
      keyId: keyId,
      keyBytes: Uint8List.fromList(_decodeBase64Url(key)),
      activatedAtUtc: DateTime.parse(activatedAtUtc).toUtc(),
    );
  }

  Future<void> _writeState(_SecureRoomState state) async {
    final encoded = jsonEncode(<String, Object?>{
      'version': 2,
      'activeRoomId': state.activeRoomId,
      'rooms': state.rooms
          .map(
            (room) => <String, Object>{
              'id': room.id,
              'name': room.name,
              'epoch': room.epoch,
              'keyId': room.keyId,
              'key': _base64UrlWithoutPadding(room.keyBytes),
              'createdAtUtc': room.createdAtUtc.toUtc().toIso8601String(),
              'keyActivatedAtUtc':
                  room.keyActivatedAtUtc.toUtc().toIso8601String(),
              'allowsLocalOwnerBootstrap': room.allowsLocalOwnerBootstrap,
              'historicalKeys': room.historicalKeys
                  .map(
                    (key) => <String, Object>{
                      'epoch': key.epoch,
                      'keyId': key.keyId,
                      'key': _base64UrlWithoutPadding(key.keyBytes),
                      'activatedAtUtc':
                          key.activatedAtUtc.toUtc().toIso8601String(),
                    },
                  )
                  .toList(growable: false),
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

  _SecureRoomState replaceRoom(SecureRoom room) {
    return _SecureRoomState(
      activeRoomId: activeRoomId,
      rooms: <SecureRoom>[
        for (final existing in rooms)
          if (existing.id == room.id) room else existing,
      ],
    );
  }

  _SecureRoomState copyWith({String? activeRoomId}) {
    return _SecureRoomState(
      activeRoomId: activeRoomId ?? this.activeRoomId,
      rooms: rooms,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
