import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_chunker.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';

void main() {
  group('MessageChunker', () {
    test('splits an encoded envelope within MTU payload limits', () {
      const overhead = 24;
      const mtu = 80;
      const chunker = MessageChunker(headerOverheadBytes: overhead);
      final envelope = _message('x' * 300);

      final chunks = chunker.chunk(envelope, negotiatedMtu: mtu);

      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.payload.length <= mtu - overhead), isTrue);
      expect(chunks.map((chunk) => chunk.index), orderedEquals(<int>[0, 1, 2, 3, 4, 5, 6, 7]));
      expect(chunks.every((chunk) => chunk.total == chunks.length), isTrue);
    });

    test('rejects an MTU that cannot fit protocol headers', () {
      const chunker = MessageChunker(headerOverheadBytes: 24);

      expect(
        () => chunker.chunk(_message('hello'), negotiatedMtu: 24),
        throwsArgumentError,
      );
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
