import 'package:meshtalk_app/core/storage/stored_chat_message.dart';

abstract interface class MessageStore {
  Future<List<StoredChatMessage>> loadRoom(String roomId);
  Future<List<StoredChatMessage>> loadPendingOutbound();
  Future<void> upsert(StoredChatMessage message);
  Future<void> markSent(String messageId);
  Future<void> close();
}
