import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/message_codec.dart';
import 'package:meshtalk_app/core/storage/message_store.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class SqliteMessageStore implements MessageStore {
  SqliteMessageStore({
    DatabaseFactory? databaseFactoryOverride,
    String? databasePath,
    MessageCodec codec = const MessageCodec(),
  })  : _databaseFactory = databaseFactoryOverride ?? databaseFactory,
        _databasePath = databasePath,
        _codec = codec;

  static const String _table = 'messages';

  final DatabaseFactory _databaseFactory;
  final String? _databasePath;
  final MessageCodec _codec;

  Future<Database>? _databaseFuture;

  @override
  Future<List<StoredChatMessage>> loadRoom(String roomId) async {
    final database = await _database();
    final rows = await database.query(
      _table,
      where: 'room_id = ?',
      whereArgs: <Object?>[roomId],
      orderBy: 'timestamp_ms ASC, id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<StoredChatMessage>> loadPendingOutbound() async {
    final database = await _database();
    final rows = await database.query(
      _table,
      where: 'direction = ? AND delivery_status = ?',
      whereArgs: <Object?>[
        StoredMessageDirection.outgoing.name,
        StoredDeliveryStatus.queued.name,
      ],
      orderBy: 'timestamp_ms ASC, id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> upsert(StoredChatMessage message) async {
    final database = await _database();
    await database.insert(
      _table,
      _toRow(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> markSent(String messageId) async {
    final database = await _database();
    await database.update(
      _table,
      <String, Object?>{
        'delivery_status': StoredDeliveryStatus.sent.name,
      },
      where: 'id = ? AND direction = ?',
      whereArgs: <Object?>[
        messageId,
        StoredMessageDirection.outgoing.name,
      ],
    );
  }

  @override
  Future<void> close() async {
    final future = _databaseFuture;
    _databaseFuture = null;
    if (future != null) {
      final database = await future;
      await database.close();
    }
  }

  Future<Database> _database() {
    return _databaseFuture ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    final databasePath = _databasePath ??
        path.join(await getDatabasesPath(), 'meshtalk_messages.db');
    return _databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE $_table (
              id TEXT PRIMARY KEY,
              room_id TEXT NOT NULL,
              timestamp_ms INTEGER NOT NULL,
              envelope BLOB NOT NULL,
              sender_label TEXT NOT NULL,
              direction TEXT NOT NULL,
              delivery_status TEXT NOT NULL
            )
          ''');
          await database.execute(
            'CREATE INDEX messages_room_time '
            'ON $_table(room_id, timestamp_ms)',
          );
          await database.execute(
            'CREATE INDEX messages_pending '
            'ON $_table(direction, delivery_status, timestamp_ms)',
          );
        },
      ),
    );
  }

  Map<String, Object?> _toRow(StoredChatMessage message) {
    final envelope = message.envelope;
    return <String, Object?>{
      'id': envelope.id,
      'room_id': envelope.roomId,
      'timestamp_ms': envelope.timestampUtc.millisecondsSinceEpoch,
      'envelope': _codec.encode(envelope),
      'sender_label': message.senderLabel,
      'direction': message.direction.name,
      'delivery_status': message.deliveryStatus.name,
    };
  }

  StoredChatMessage _fromRow(Map<String, Object?> row) {
    final envelopeBytes = row['envelope'];
    if (envelopeBytes is! Uint8List) {
      throw const FormatException('Stored message envelope is not a BLOB.');
    }

    return StoredChatMessage(
      envelope: _codec.decode(envelopeBytes),
      senderLabel: row['sender_label']! as String,
      direction: StoredMessageDirection.values.byName(
        row['direction']! as String,
      ),
      deliveryStatus: StoredDeliveryStatus.values.byName(
        row['delivery_status']! as String,
      ),
    );
  }
}
