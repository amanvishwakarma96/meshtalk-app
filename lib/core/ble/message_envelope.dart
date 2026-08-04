import 'dart:typed_data';

class MessageEnvelope {
  MessageEnvelope({
    required this.id,
    required this.senderId,
    required this.roomId,
    required this.timestampUtc,
    required this.hopLimit,
    required Uint8List payload,
  }) : payload = Uint8List.fromList(payload) {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (senderId.isEmpty) {
      throw ArgumentError.value(senderId, 'senderId', 'Must not be empty.');
    }
    if (roomId.isEmpty) {
      throw ArgumentError.value(roomId, 'roomId', 'Must not be empty.');
    }
    if (hopLimit < 0) {
      throw ArgumentError.value(hopLimit, 'hopLimit', 'Must be non-negative.');
    }
  }

  final String id;
  final String senderId;
  final String roomId;
  final DateTime timestampUtc;
  final int hopLimit;
  final Uint8List payload;

  MessageEnvelope copyWith({
    String? id,
    String? senderId,
    String? roomId,
    DateTime? timestampUtc,
    int? hopLimit,
    Uint8List? payload,
  }) {
    return MessageEnvelope(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      roomId: roomId ?? this.roomId,
      timestampUtc: timestampUtc ?? this.timestampUtc,
      hopLimit: hopLimit ?? this.hopLimit,
      payload: payload ?? this.payload,
    );
  }
}
