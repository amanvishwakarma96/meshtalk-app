import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:mocktail/mocktail.dart';

class MockChatTransport extends Mock implements ChatTransport {}

void main() {
  setUpAll(() {
    registerFallbackValue(_message('fallback'));
  });

  group('TransportManager', () {
    late MockChatTransport ble;
    late MockChatTransport wifi;
    late MockChatTransport relay;

    setUp(() {
      ble = MockChatTransport();
      wifi = MockChatTransport();
      relay = MockChatTransport();
      for (final transport in <MockChatTransport>[ble, wifi, relay]) {
        when(transport.connect).thenAnswer((_) async {});
        when(transport.disconnect).thenAnswer((_) async {});
        when(() => transport.send(any())).thenAnswer((_) async {});
      }
    });

    test('selects the first available transport by priority', () async {
      when(ble.isAvailable).thenAnswer((_) async => false);
      when(wifi.isAvailable).thenAnswer((_) async => true);
      when(relay.isAvailable).thenAnswer((_) async => true);
      final manager =
          TransportManager(transports: <ChatTransport>[ble, wifi, relay]);

      final selected = await manager.refresh();

      expect(selected, same(wifi));
      verify(wifi.connect).called(1);
      verifyNever(relay.isAvailable);
      await manager.dispose();
    });

    test('queues with no transport and flushes after fallback connects',
        () async {
      when(ble.isAvailable).thenAnswer((_) async => false);
      when(wifi.isAvailable).thenAnswer((_) async => true);
      final manager = TransportManager(transports: <ChatTransport>[ble, wifi]);
      final message = _message('queued');

      await manager.send(message);
      expect(manager.pendingCount, 1);
      await manager.refresh();

      verify(() => wifi.send(message)).called(1);
      expect(manager.pendingCount, 0);
      await manager.dispose();
    });

    test('upgrades from Wi-Fi to BLE and disconnects previous transport',
        () async {
      var bleAvailable = false;
      when(ble.isAvailable).thenAnswer((_) async => bleAvailable);
      when(wifi.isAvailable).thenAnswer((_) async => true);
      final manager = TransportManager(transports: <ChatTransport>[ble, wifi]);

      expect(await manager.refresh(), same(wifi));
      bleAvailable = true;
      expect(await manager.refresh(), same(ble));

      verify(ble.connect).called(1);
      verify(wifi.disconnect).called(1);
      expect(manager.active, same(ble));
      await manager.dispose();
    });
  });
}

MessageEnvelope _message(String id) {
  return MessageEnvelope(
    id: id,
    senderId: 'device-a',
    roomId: 'room-1',
    timestampUtc: DateTime.utc(2026, 8, 4),
    hopLimit: 4,
    payload: Uint8List.fromList(<int>[1, 2, 3]),
  );
}
