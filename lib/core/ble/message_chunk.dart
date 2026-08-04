import 'dart:typed_data';

class MessageChunk {
  MessageChunk({
    required this.messageId,
    required this.index,
    required this.total,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload);

  final String messageId;
  final int index;
  final int total;
  final Uint8List payload;
}
