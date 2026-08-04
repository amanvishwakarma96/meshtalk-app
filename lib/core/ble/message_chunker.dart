import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/message_chunk.dart';
import 'package:meshtalk_app/core/ble/message_codec.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';

class MessageChunker {
  const MessageChunker({
    this.codec = const MessageCodec(),
    this.headerOverheadBytes = 24,
  });

  final MessageCodec codec;
  final int headerOverheadBytes;

  List<MessageChunk> chunk(
    MessageEnvelope envelope, {
    required int negotiatedMtu,
  }) {
    final chunkPayloadSize = negotiatedMtu - headerOverheadBytes;
    if (chunkPayloadSize <= 0) {
      throw ArgumentError.value(
        negotiatedMtu,
        'negotiatedMtu',
        'MTU must exceed protocol header overhead.',
      );
    }

    final encoded = codec.encode(envelope);
    final total = math.max(1, (encoded.length / chunkPayloadSize).ceil());

    return List<MessageChunk>.generate(total, (index) {
      final start = index * chunkPayloadSize;
      final end = math.min(start + chunkPayloadSize, encoded.length);
      return MessageChunk(
        messageId: envelope.id,
        index: index,
        total: total,
        payload: Uint8List.fromList(encoded.sublist(start, end)),
      );
    });
  }
}
