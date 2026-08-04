import 'dart:convert';
import 'dart:typed_data';

import 'package:meshtalk_app/core/ble/message_envelope.dart';

class MessageCodec {
  const MessageCodec();

  Uint8List encode(MessageEnvelope envelope) {
    final json = <String, Object>{
      'id': envelope.id,
      'senderId': envelope.senderId,
      'roomId': envelope.roomId,
      'timestampUtc': envelope.timestampUtc.toUtc().toIso8601String(),
      'hopLimit': envelope.hopLimit,
      'payload': base64Encode(envelope.payload),
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  MessageEnvelope decode(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Message envelope must be a JSON object.');
    }

    final id = decoded['id'];
    final senderId = decoded['senderId'];
    final roomId = decoded['roomId'];
    final timestamp = decoded['timestampUtc'];
    final hopLimit = decoded['hopLimit'];
    final payload = decoded['payload'];

    if (id is! String ||
        senderId is! String ||
        roomId is! String ||
        timestamp is! String ||
        hopLimit is! int ||
        payload is! String) {
      throw const FormatException('Message envelope contains invalid fields.');
    }

    return MessageEnvelope(
      id: id,
      senderId: senderId,
      roomId: roomId,
      timestampUtc: DateTime.parse(timestamp).toUtc(),
      hopLimit: hopLimit,
      payload: Uint8List.fromList(base64Decode(payload)),
    );
  }
}
