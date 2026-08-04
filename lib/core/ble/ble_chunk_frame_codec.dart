import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/message_chunk.dart';

class BleChunkFrameCodec {
  const BleChunkFrameCodec();

  static const int protocolVersion = 1;
  static const int headerBytes = 19;
  static const int maximumChunks = 255;

  Uint8List encode(MessageChunk chunk) {
    if (chunk.total <= 0 || chunk.total > maximumChunks) {
      throw FormatException(
        'BLE chunk total must be between 1 and $maximumChunks.',
      );
    }
    if (chunk.index < 0 || chunk.index >= chunk.total) {
      throw const FormatException(
        'BLE chunk index is outside the valid range.',
      );
    }

    final uuidBytes = _uuidToBytes(chunk.messageId);
    final frame = Uint8List(headerBytes + chunk.payload.length)
      ..[0] = protocolVersion
      ..setRange(1, 17, uuidBytes)
      ..[17] = chunk.index
      ..[18] = chunk.total
      ..setRange(
        headerBytes,
        headerBytes + chunk.payload.length,
        chunk.payload,
      );
    return frame;
  }

  MessageChunk decode(Uint8List frame) {
    if (frame.length < headerBytes) {
      throw const FormatException('BLE frame is shorter than its header.');
    }
    if (frame[0] != protocolVersion) {
      throw FormatException('Unsupported BLE frame version ${frame[0]}.');
    }

    final index = frame[17];
    final total = frame[18];
    if (total == 0 || index >= total) {
      throw const FormatException('BLE frame chunk metadata is invalid.');
    }

    return MessageChunk(
      messageId: _bytesToUuid(frame.sublist(1, 17)),
      index: index,
      total: total,
      payload: Uint8List.fromList(frame.sublist(headerBytes)),
    );
  }

  Uint8List _uuidToBytes(String value) {
    final normalized = value.replaceAll('-', '').toLowerCase();
    if (normalized.length != 32 ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(normalized)) {
      throw FormatException('Message ID must be a canonical UUID: $value');
    }

    return Uint8List.fromList(
      List<int>.generate(
        16,
        (index) => int.parse(
          normalized.substring(index * 2, index * 2 + 2),
          radix: 16,
        ),
      ),
    );
  }

  String _bytesToUuid(List<int> bytes) {
    if (bytes.length != 16) {
      throw const FormatException('A UUID must contain exactly 16 bytes.');
    }

    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
