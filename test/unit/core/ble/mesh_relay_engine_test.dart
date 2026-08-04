import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/mesh_relay_engine.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/ble/seen_message_cache.dart';

void main() {
  group('MeshRelayEngine', () {
    test('delivers and decrements hop limit for relay', () {
      final engine = MeshRelayEngine();

      final decision = engine.processIncoming(_message(id: 'a', hopLimit: 3));

      expect(decision.disposition, RelayDisposition.deliverAndRelay);
      expect(decision.deliverLocally, isTrue);
      expect(decision.relayEnvelope!.hopLimit, 2);
      expect(decision.relayEnvelope!.id, 'a');
    });

    test('does not deliver or relay a duplicate', () {
      final engine = MeshRelayEngine();
      final message = _message(id: 'duplicate', hopLimit: 3);

      engine.processIncoming(message);
      final duplicate = engine.processIncoming(message);

      expect(duplicate.disposition, RelayDisposition.duplicate);
      expect(duplicate.deliverLocally, isFalse);
      expect(duplicate.relayEnvelope, isNull);
    });

    test('does not deliver an echoed locally originated message', () {
      final engine = MeshRelayEngine();
      engine.markOriginated('local-message');

      final echoed = engine.processIncoming(
        _message(id: 'local-message', hopLimit: 3),
      );

      expect(echoed.disposition, RelayDisposition.duplicate);
      expect(echoed.deliverLocally, isFalse);
    });

    test('drops a message whose hop limit is zero', () {
      final decision = MeshRelayEngine().processIncoming(
        _message(id: 'expired', hopLimit: 0),
      );

      expect(decision.disposition, RelayDisposition.expired);
      expect(decision.deliverLocally, isFalse);
      expect(decision.relayEnvelope, isNull);
    });

    test('bounded cache evicts the oldest message', () {
      final cache = SeenMessageCache(maxEntries: 2);

      expect(cache.markSeen('first'), isTrue);
      expect(cache.markSeen('second'), isTrue);
      expect(cache.markSeen('third'), isTrue);
      expect(cache.length, 2);
      expect(cache.markSeen('first'), isTrue);
    });
  });
}

MessageEnvelope _message({required String id, required int hopLimit}) {
  return MessageEnvelope(
    id: id,
    senderId: 'device-a',
    roomId: 'room-1',
    timestampUtc: DateTime.utc(2026, 8, 4),
    hopLimit: hopLimit,
    payload: Uint8List.fromList(<int>[1, 2, 3]),
  );
}
