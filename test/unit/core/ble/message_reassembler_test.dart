import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_chunker.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/ble/message_reassembler.dart';

void main() {
  group('MessageReassembler', () {
    test('reassembles out-of-order chunks and ignores duplicates', () {
      final envelope = _message('mesh payload ' * 40);
      const chunker = MessageChunker();
      final chunks =
          chunker.chunk(envelope, negotiatedMtu: 72).reversed.toList();
      final reassembler = MessageReassembler();

      expect(reassembler.add(chunks.first), isNull);
      expect(reassembler.add(chunks.first), isNull);

      MessageEnvelope? completed;
      for (final chunk in chunks.skip(1)) {
        completed = reassembler.add(chunk) ?? completed;
      }

      expect(completed, isNotNull);
      expect(completed!.id, envelope.id);
      expect(utf8.decode(completed.payload), utf8.decode(envelope.payload));
      expect(reassembler.pendingAssemblyCount, 0);
    });

    test('discards incomplete messages after the timeout', () {
      var now = DateTime.utc(2026, 8, 4, 9);
      final reassembler = MessageReassembler(
        timeout: const Duration(seconds: 30),
        clock: () => now,
      );
      final chunks = const MessageChunker().chunk(
        _message('payload ' * 50),
        negotiatedMtu: 64,
      );

      reassembler.add(chunks.first);
      expect(reassembler.pendingAssemblyCount, 1);

      now = now.add(const Duration(seconds: 30));
      expect(reassembler.discardExpired(), 1);
      expect(reassembler.pendingAssemblyCount, 0);
    });
  });
}

MessageEnvelope _message(String text) {
  return MessageEnvelope(
    id: 'message-1',
    senderId: 'device-a',
    roomId: 'room-1',
    timestampUtc: DateTime.utc(2026, 8, 4),
    hopLimit: 4,
    payload: Uint8List.fromList(utf8.encode(text)),
  );
}
