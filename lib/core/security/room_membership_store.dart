import 'dart:convert';

import 'package:meshtalk_app/core/security/room_membership.dart';
import 'package:meshtalk_app/core/security/secure_room_store.dart';

class RoomMembershipStore {
  RoomMembershipStore({
    required SecureValueStore values,
    RoomMembershipCodec? codec,
  })  : _values = values,
        _codec = codec ?? RoomMembershipCodec();

  static const String _storageKey = 'meshtalk.room-memberships.v1';
  static const int _maximumMemberships = 128;

  final SecureValueStore _values;
  final RoomMembershipCodec _codec;

  Future<List<RoomMembership>> listRoom(String roomId) async {
    final all = await _readAll();
    final room = all
        .where((membership) => membership.roomId == roomId)
        .toList(growable: false)
      ..sort((left, right) {
        final epoch = right.epoch.compareTo(left.epoch);
        if (epoch != 0) {
          return epoch;
        }
        return left.memberDeviceId.compareTo(right.memberDeviceId);
      });
    return List<RoomMembership>.unmodifiable(room);
  }

  Future<List<RoomMembership>> listCurrentEpoch(
    String roomId,
    int epoch,
  ) async {
    return List<RoomMembership>.unmodifiable(
      (await listRoom(roomId)).where((membership) => membership.epoch == epoch),
    );
  }

  Future<RoomMembership?> membershipFor({
    required String roomId,
    required String deviceId,
    int? epoch,
  }) async {
    final memberships = await listRoom(roomId);
    for (final membership in memberships) {
      if (membership.memberDeviceId == deviceId &&
          (epoch == null || membership.epoch == epoch)) {
        return membership;
      }
    }
    return null;
  }

  Future<RoomMembership?> ownerFor(String roomId, int epoch) async {
    for (final membership in await listCurrentEpoch(roomId, epoch)) {
      if (membership.role == RoomMemberRole.owner) {
        return membership;
      }
    }
    return null;
  }

  Future<void> upsert(RoomMembership membership) async {
    if (!await _codec.verify(membership)) {
      throw const FormatException('Room membership signature is invalid.');
    }
    final all = await _readAll();
    final updated = <RoomMembership>[
      for (final existing in all)
        if (!(existing.roomId == membership.roomId &&
            existing.epoch == membership.epoch &&
            existing.memberDeviceId == membership.memberDeviceId))
          existing,
      membership,
    ];
    if (updated.length > _maximumMemberships) {
      throw StateError('Room membership storage limit reached.');
    }
    await _writeAll(updated);
  }

  Future<void> replaceEpoch({
    required String roomId,
    required int epoch,
    required List<RoomMembership> memberships,
  }) async {
    if (memberships.isEmpty) {
      throw ArgumentError('A room epoch must retain at least its owner.');
    }
    for (final membership in memberships) {
      if (membership.roomId != roomId || membership.epoch != epoch) {
        throw ArgumentError('Replacement membership belongs to another epoch.');
      }
      if (!await _codec.verify(membership)) {
        throw const FormatException('Room membership signature is invalid.');
      }
    }
    final ownerCount = memberships
        .where((membership) => membership.role == RoomMemberRole.owner)
        .length;
    if (ownerCount != 1) {
      throw StateError('A room epoch must contain exactly one owner.');
    }
    final deviceIds = <String>{};
    for (final membership in memberships) {
      if (!deviceIds.add(membership.memberDeviceId)) {
        throw StateError('Room epoch contains a duplicate member identity.');
      }
    }

    final all = await _readAll();
    final updated = <RoomMembership>[
      for (final existing in all)
        if (!(existing.roomId == roomId && existing.epoch == epoch)) existing,
      ...memberships,
    ];
    if (updated.length > _maximumMemberships) {
      throw StateError('Room membership storage limit reached.');
    }
    await _writeAll(updated);
  }

  Future<void> removeRoom(String roomId) async {
    final all = await _readAll();
    await _writeAll(
      all.where((membership) => membership.roomId != roomId).toList(),
    );
  }

  Future<List<RoomMembership>> _readAll() async {
    final encoded = await _values.read(_storageKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return const <RoomMembership>[];
    }
    try {
      final raw = jsonDecode(encoded);
      if (raw is! Map<String, dynamic> || raw['version'] != 1) {
        throw const FormatException('Unsupported membership storage version.');
      }
      final entries = raw['memberships'];
      if (entries is! List<dynamic>) {
        throw const FormatException('Membership storage is malformed.');
      }
      if (entries.length > _maximumMemberships) {
        throw const FormatException('Membership storage exceeds its limit.');
      }
      final memberships = <RoomMembership>[];
      for (final entry in entries) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Membership entry must be an object.');
        }
        final membership = _codec.decode(jsonEncode(entry));
        if (!await _codec.verify(membership)) {
          throw const FormatException('Stored membership signature is invalid.');
        }
        memberships.add(membership);
      }
      return List<RoomMembership>.unmodifiable(memberships);
    } on FormatException catch (error) {
      throw StateError('Room membership storage is corrupt: ${error.message}');
    } on Object catch (error) {
      throw StateError('Room membership storage is corrupt: $error');
    }
  }

  Future<void> _writeAll(List<RoomMembership> memberships) async {
    await _values.write(
      _storageKey,
      jsonEncode(<String, Object>{
        'version': 1,
        'memberships': memberships
            .map((membership) => membership.toJson())
            .toList(growable: false),
      }),
    );
  }
}
