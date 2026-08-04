import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/mesh_relay_engine.dart';
import 'package:meshtalk_app/core/ble/message_chunker.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/ble/message_reassembler.dart';

void main() {
  test('mocked peer receives, reassembles, and relays a message', () {
    final outbound = MessageEnvelope(
      id: 'exchange-1',
      senderId: 'peer-a',
      roomId: 'trail-room',
      timestampUtc: DateTime.utc(2026, 8, 4),
      hopLimit: 3,
      payload: Uint8List.fromList(utf8.encode('hello from peer A ' * 20)),
    );
    final chunks = const MessageChunker().chunk(outbound, negotiatedMtu: 72);
    final peerBReassembler = MessageReassembler();

    MessageEnvelope? received;
    for (final chunk in chunks.reversed) {
      received = peerBReassembler.add(chunk) ?? received;
    }

    expect(received, isNotNull);
    expect(utf8.decode(received!.payload), utf8.decode(outbound.payload));

    final decision = MeshRelayEngine().processIncoming(received);
    expect(decision.deliverLocally, isTrue);
    expect(decision.relayEnvelope!.hopLimit, 2);
    expect(decision.relayEnvelope!.id, outbound.id);
  });
}
