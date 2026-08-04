import 'package:meshtalk_app/core/ble/message_envelope.dart';

enum StoredMessageDirection { outgoing, incoming }

enum StoredDeliveryStatus { queued, sent, received }

class StoredChatMessage {
  const StoredChatMessage({
    required this.envelope,
    required this.senderLabel,
    required this.direction,
    required this.deliveryStatus,
  });

  final MessageEnvelope envelope;
  final String senderLabel;
  final StoredMessageDirection direction;
  final StoredDeliveryStatus deliveryStatus;

  StoredChatMessage copyWith({StoredDeliveryStatus? deliveryStatus}) {
    return StoredChatMessage(
      envelope: envelope,
      senderLabel: senderLabel,
      direction: direction,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }
}
