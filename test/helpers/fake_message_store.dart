import 'package:meshtalk_app/core/storage/message_store.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';

class FakeMessageStore implements MessageStore {
  final Map<String, StoredChatMessage> _messages =
      <String, StoredChatMessage>{};

  List<StoredChatMessage> get messages {
    final values = _messages.values.toList(growable: false)
      ..sort(
        (a, b) => a.envelope.timestampUtc.compareTo(b.envelope.timestampUtc),
      );
    return values;
  }

  @override
  Future<void> close() async {}

  @override
  Future<List<StoredChatMessage>> loadPendingOutbound() async {
    return messages
        .where(
          (message) =>
              message.direction == StoredMessageDirection.outgoing &&
              message.deliveryStatus == StoredDeliveryStatus.queued,
        )
        .toList(growable: false);
  }

  @override
  Future<List<StoredChatMessage>> loadRoom(String roomId) async {
    return messages
        .where((message) => message.envelope.roomId == roomId)
        .toList(growable: false);
  }

  @override
  Future<void> markSent(String messageId) async {
    final existing = _messages[messageId];
    if (existing?.direction == StoredMessageDirection.outgoing) {
      _messages[messageId] = existing!.copyWith(
        deliveryStatus: StoredDeliveryStatus.sent,
      );
    }
  }

  @override
  Future<void> upsert(StoredChatMessage message) async {
    _messages[message.envelope.id] = message;
  }
}
