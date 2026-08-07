import 'dart:typed_data';

class SecureRoomEpochKey {
  SecureRoomEpochKey({
    required this.epoch,
    required this.keyId,
    required Uint8List keyBytes,
    required this.activatedAtUtc,
  }) : keyBytes = Uint8List.fromList(keyBytes) {
    if (epoch < 1) {
      throw ArgumentError.value(epoch, 'epoch', 'Room epoch must be positive.');
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

  final int epoch;
  final String keyId;
  final Uint8List keyBytes;
  final DateTime activatedAtUtc;
}

class SecureRoom {
  SecureRoom({
    required this.id,
    required this.name,
    required this.keyId,
    required Uint8List keyBytes,
    required this.createdAtUtc,
    this.epoch = 1,
    this.allowsLocalOwnerBootstrap = true,
    DateTime? keyActivatedAtUtc,
    List<SecureRoomEpochKey> historicalKeys = const <SecureRoomEpochKey>[],
  })  : keyBytes = Uint8List.fromList(keyBytes),
        keyActivatedAtUtc = (keyActivatedAtUtc ?? createdAtUtc).toUtc(),
        historicalKeys = List<SecureRoomEpochKey>.unmodifiable(historicalKeys) {
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
    if (epoch < 1) {
      throw ArgumentError.value(epoch, 'epoch', 'Room epoch must be positive.');
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
    final seenEpochs = <int>{epoch};
    final seenKeyIds = <String>{keyId};
    for (final historical in this.historicalKeys) {
      if (historical.epoch >= epoch) {
        throw ArgumentError(
          'Historical room keys must be older than the current epoch.',
        );
      }
      if (!seenEpochs.add(historical.epoch) ||
          !seenKeyIds.add(historical.keyId)) {
        throw ArgumentError(
          'Room key history contains duplicate epochs or keys.',
        );
      }
    }
  }

  final String id;
  final String name;
  final int epoch;
  final String keyId;
  final Uint8List keyBytes;
  final DateTime createdAtUtc;
  final DateTime keyActivatedAtUtc;
  final bool allowsLocalOwnerBootstrap;
  final List<SecureRoomEpochKey> historicalKeys;

  SecureRoomEpochKey get currentKey => SecureRoomEpochKey(
        epoch: epoch,
        keyId: keyId,
        keyBytes: keyBytes,
        activatedAtUtc: keyActivatedAtUtc,
      );

  List<SecureRoomEpochKey> get keyRing => List<SecureRoomEpochKey>.unmodifiable(
        <SecureRoomEpochKey>[...historicalKeys, currentKey]
          ..sort((left, right) => left.epoch.compareTo(right.epoch)),
      );

  SecureRoomEpochKey? keyForId(String candidateKeyId) {
    if (candidateKeyId == keyId) {
      return currentKey;
    }
    for (final historical in historicalKeys) {
      if (historical.keyId == candidateKeyId) {
        return historical;
      }
    }
    return null;
  }

  SecureRoom roomForKeyId(String candidateKeyId) {
    final key = keyForId(candidateKeyId);
    if (key == null) {
      throw StateError('Room key is not present in the local epoch key ring.');
    }
    if (key.keyId == keyId) {
      return this;
    }
    return SecureRoom(
      id: id,
      name: name,
      epoch: key.epoch,
      keyId: key.keyId,
      keyBytes: key.keyBytes,
      createdAtUtc: createdAtUtc,
      keyActivatedAtUtc: key.activatedAtUtc,
      allowsLocalOwnerBootstrap: false,
    );
  }

  SecureRoom rotateTo({
    required String newKeyId,
    required Uint8List newKeyBytes,
    required DateTime activatedAtUtc,
    int maximumHistoricalKeys = 8,
  }) {
    if (maximumHistoricalKeys < 1) {
      throw ArgumentError.value(
        maximumHistoricalKeys,
        'maximumHistoricalKeys',
        'At least one historical key must be retained.',
      );
    }
    final history = <SecureRoomEpochKey>[
      ...historicalKeys,
      currentKey,
    ];
    final retained = history.length <= maximumHistoricalKeys
        ? history
        : history.sublist(history.length - maximumHistoricalKeys);
    return SecureRoom(
      id: id,
      name: name,
      epoch: epoch + 1,
      keyId: newKeyId,
      keyBytes: newKeyBytes,
      createdAtUtc: createdAtUtc,
      keyActivatedAtUtc: activatedAtUtc,
      allowsLocalOwnerBootstrap: allowsLocalOwnerBootstrap,
      historicalKeys: retained,
    );
  }

  SecureRoomSummary get summary => SecureRoomSummary(
        id: id,
        name: name,
        epoch: epoch,
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
    this.epoch = 1,
  });

  final String id;
  final String name;
  final int epoch;
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
