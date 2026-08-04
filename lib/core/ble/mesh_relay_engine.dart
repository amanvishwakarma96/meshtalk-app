import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/ble/seen_message_cache.dart';

enum RelayDisposition {
  duplicate,
  expired,
  deliveredOnly,
  deliverAndRelay,
}

class RelayDecision {
  const RelayDecision({
    required this.disposition,
    required this.deliverLocally,
    this.relayEnvelope,
  });

  final RelayDisposition disposition;
  final bool deliverLocally;
  final MessageEnvelope? relayEnvelope;
}

class MeshRelayEngine {
  MeshRelayEngine({SeenMessageCache? seenMessages})
      : _seenMessages = seenMessages ?? SeenMessageCache();

  final SeenMessageCache _seenMessages;

  RelayDecision processIncoming(MessageEnvelope envelope) {
    if (!_seenMessages.markSeen(envelope.id)) {
      return const RelayDecision(
        disposition: RelayDisposition.duplicate,
        deliverLocally: false,
      );
    }

    if (envelope.hopLimit == 0) {
      return const RelayDecision(
        disposition: RelayDisposition.expired,
        deliverLocally: false,
      );
    }

    if (envelope.hopLimit == 1) {
      return const RelayDecision(
        disposition: RelayDisposition.deliveredOnly,
        deliverLocally: true,
      );
    }

    return RelayDecision(
      disposition: RelayDisposition.deliverAndRelay,
      deliverLocally: true,
      relayEnvelope: envelope.copyWith(hopLimit: envelope.hopLimit - 1),
    );
  }
}
