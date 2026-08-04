import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/ble_chunk_frame_codec.dart';
import 'package:meshtalk_app/core/ble/message_chunk.dart';

void main() {
  const codec = BleChunkFrameCodec();
  const messageId = '550e8400-e29b-41d4-a716-446655440000';

  test('round-trips a compact BLE chunk frame', () {
    final chunk = MessageChunk(
      messageId: messageId,
      index: 2,
      total: 5,
      payload: Uint8List.fromList(<int>[1, 2, 3, 4]),
    );

    final frame = codec.encode(chunk);
    final decoded = codec.decode(frame);

    expect(frame.length, BleChunkFrameCodec.headerBytes + 4);
    expect(decoded.messageId, messageId);
    expect(decoded.index, 2);
    expect(decoded.total, 5);
    expect(decoded.payload, <int>[1, 2, 3, 4]);
  });

  test('rejects non-UUID message identifiers', () {
    final chunk = MessageChunk(
      messageId: 'not-a-uuid',
      index: 0,
      total: 1,
      payload: Uint8List(0),
    );

    expect(() => codec.encode(chunk), throwsFormatException);
  });

  test('rejects unsupported protocol versions', () {
    final frame = Uint8List(BleChunkFrameCodec.headerBytes)
      ..[0] = BleChunkFrameCodec.protocolVersion + 1
      ..[18] = 1;

    expect(() => codec.decode(frame), throwsFormatException);
  });

  test('rejects invalid chunk indexes', () {
    final frame = Uint8List(BleChunkFrameCodec.headerBytes)
      ..[0] = BleChunkFrameCodec.protocolVersion
      ..[17] = 1
      ..[18] = 1;

    expect(() => codec.decode(frame), throwsFormatException);
  });
}
