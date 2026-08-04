import 'package:meshtalk_app/core/ble/message_envelope.dart';

abstract interface class MessageStore {
  Stream<List<MessageEnvelope>> watchRoom(String roomId);
  Future<void> save(MessageEnvelope message);
  Future<List<MessageEnvelope>> loadPendingOutbound();
  Future<void> markSent(String messageId);
}
