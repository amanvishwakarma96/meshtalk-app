import 'dart:collection';

import 'package:meshtalk_app/core/ble/message_reassembler.dart';

class SeenMessageCache {
  SeenMessageCache({
    this.maxEntries = 2048,
    this.entryTtl = const Duration(minutes: 10),
    UtcClock? clock,
  }) : _clock = clock ?? _systemClock {
    if (maxEntries <= 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be positive.');
    }
  }

  final int maxEntries;
  final Duration entryTtl;
  final UtcClock _clock;
  final LinkedHashMap<String, DateTime> _expiresAt =
      LinkedHashMap<String, DateTime>();

  int get length => _expiresAt.length;

  bool markSeen(String messageId) {
    if (messageId.isEmpty) {
      throw ArgumentError.value(messageId, 'messageId', 'Must not be empty.');
    }

    final now = _clock().toUtc();
    prune(now);
    final existingExpiry = _expiresAt[messageId];
    if (existingExpiry != null && existingExpiry.isAfter(now)) {
      return false;
    }

    while (_expiresAt.length >= maxEntries) {
      _expiresAt.remove(_expiresAt.keys.first);
    }
    _expiresAt[messageId] = now.add(entryTtl);
    return true;
  }

  int prune([DateTime? atUtc]) {
    final now = (atUtc ?? _clock()).toUtc();
    final before = _expiresAt.length;
    _expiresAt.removeWhere((_, expiry) => !expiry.isAfter(now));
    return before - _expiresAt.length;
  }

  static DateTime _systemClock() => DateTime.now().toUtc();
}
