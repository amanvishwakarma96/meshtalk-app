import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/storage/sqlite_message_store.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late SqliteMessageStore store;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    store = SqliteMessageStore(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await store.close();
  });

  test('persists ordered history and tracks queued outbound messages',
      () async {
    await store.upsert(
      _stored(
        id: 'later',
        text: 'second',
        timestampUtc: DateTime.utc(2026, 8, 4, 10),
        direction: StoredMessageDirection.incoming,
        deliveryStatus: StoredDeliveryStatus.received,
      ),
    );
    await store.upsert(
      _stored(
        id: 'queued',
        text: 'first',
        timestampUtc: DateTime.utc(2026, 8, 4, 9),
        direction: StoredMessageDirection.outgoing,
        deliveryStatus: StoredDeliveryStatus.queued,
      ),
    );

    final history = await store.loadRoom('nearby');
    final pending = await store.loadPendingOutbound();

    expect(history.map((message) => message.envelope.id), <String>[
      'queued',
      'later',
    ]);
    expect(pending.single.envelope.id, 'queued');

    await store.markSent('queued');

    expect(await store.loadPendingOutbound(), isEmpty);
    expect(
      (await store.loadRoom('nearby')).first.deliveryStatus,
      StoredDeliveryStatus.sent,
    );
  });

  test('upsert is idempotent by message id', () async {
    final original = _stored(
      id: 'same-id',
      text: 'payload',
      timestampUtc: DateTime.utc(2026, 8, 4),
      direction: StoredMessageDirection.outgoing,
      deliveryStatus: StoredDeliveryStatus.queued,
    );

    await store.upsert(original);
    await store.upsert(
      original.copyWith(deliveryStatus: StoredDeliveryStatus.sent),
    );

    final history = await store.loadRoom('nearby');
    expect(history, hasLength(1));
    expect(history.single.deliveryStatus, StoredDeliveryStatus.sent);
  });
}

StoredChatMessage _stored({
  required String id,
  required String text,
  required DateTime timestampUtc,
  required StoredMessageDirection direction,
  required StoredDeliveryStatus deliveryStatus,
}) {
  return StoredChatMessage(
    envelope: MessageEnvelope(
      id: id,
      senderId: direction == StoredMessageDirection.outgoing
          ? 'device-local'
          : 'device-remote',
      roomId: 'nearby',
      timestampUtc: timestampUtc,
      hopLimit: 4,
      payload: Uint8List.fromList(utf8.encode(text)),
    ),
    senderLabel: direction == StoredMessageDirection.outgoing
        ? 'Local Phone'
        : 'Peer Phone',
    direction: direction,
    deliveryStatus: deliveryStatus,
  );
}
