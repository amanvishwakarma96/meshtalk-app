import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/message_chunk.dart';
import 'package:meshtalk_app/core/ble/message_codec.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';

typedef UtcClock = DateTime Function();

class MessageReassembler {
  MessageReassembler({
    this.codec = const MessageCodec(),
    this.timeout = const Duration(seconds: 30),
    UtcClock? clock,
  }) : _clock = clock ?? _systemClock;

  final MessageCodec codec;
  final Duration timeout;
  final UtcClock _clock;
  final Map<String, _ChunkAssembly> _assemblies = <String, _ChunkAssembly>{};

  int get pendingAssemblyCount => _assemblies.length;

  MessageEnvelope? add(MessageChunk chunk) {
    final now = _clock().toUtc();
    discardExpired(now);
    _validate(chunk);

    final assembly = _assemblies.putIfAbsent(
      chunk.messageId,
      () => _ChunkAssembly(total: chunk.total, lastUpdatedUtc: now),
    );

    if (assembly.total != chunk.total) {
      _assemblies.remove(chunk.messageId);
      throw const FormatException('Chunk total changed during reassembly.');
    }

    assembly
      ..chunks.putIfAbsent(chunk.index, () => chunk.payload)
      ..lastUpdatedUtc = now;

    if (assembly.chunks.length != assembly.total) {
      return null;
    }

    final builder = BytesBuilder(copy: false);
    for (var index = 0; index < assembly.total; index++) {
      final bytes = assembly.chunks[index];
      if (bytes == null) {
        return null;
      }
      builder.add(bytes);
    }

    _assemblies.remove(chunk.messageId);
    final envelope = codec.decode(builder.takeBytes());
    if (envelope.id != chunk.messageId) {
      throw const FormatException('Chunk message ID does not match envelope ID.');
    }
    return envelope;
  }

  int discardExpired([DateTime? atUtc]) {
    final now = (atUtc ?? _clock()).toUtc();
    final before = _assemblies.length;
    _assemblies.removeWhere(
      (_, assembly) => !assembly.lastUpdatedUtc.add(timeout).isAfter(now),
    );
    return before - _assemblies.length;
  }

  void _validate(MessageChunk chunk) {
    if (chunk.messageId.isEmpty) {
      throw const FormatException('Chunk message ID must not be empty.');
    }
    if (chunk.total <= 0) {
      throw const FormatException('Chunk total must be positive.');
    }
    if (chunk.index < 0 || chunk.index >= chunk.total) {
      throw const FormatException('Chunk index is outside the valid range.');
    }
  }

  static DateTime _systemClock() => DateTime.now().toUtc();
}

class _ChunkAssembly {
  _ChunkAssembly({required this.total, required this.lastUpdatedUtc});

  final int total;
  final Map<int, Uint8List> chunks = <int, Uint8List>{};
  DateTime lastUpdatedUtc;
}
