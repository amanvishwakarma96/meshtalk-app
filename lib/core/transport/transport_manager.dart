import 'dart:async';

import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';

class TransportManager {
  TransportManager({required List<ChatTransport> transports})
      : _transports = List<ChatTransport>.unmodifiable(transports) {
    if (transports.isEmpty) {
      throw ArgumentError.value(transports, 'transports', 'Must not be empty.');
    }
  }

  final List<ChatTransport> _transports;
  final List<MessageEnvelope> _pending = <MessageEnvelope>[];
  final StreamController<ChatTransport?> _changes =
      StreamController<ChatTransport?>.broadcast();

  ChatTransport? _active;

  ChatTransport? get active => _active;
  int get pendingCount => _pending.length;
  Stream<ChatTransport?> get changes => _changes.stream;

  Future<ChatTransport?> refresh() async {
    ChatTransport? candidate;
    for (final transport in _transports) {
      if (await transport.isAvailable()) {
        candidate = transport;
        break;
      }
    }

    if (identical(candidate, _active)) {
      if (_active != null) {
        await _flushPending();
      }
      return _active;
    }

    final previous = _active;
    if (candidate == null) {
      _active = null;
      _changes.add(null);
      if (previous != null) {
        await previous.disconnect();
      }
      return null;
    }

    await candidate.connect();
    _active = candidate;
    _changes.add(candidate);
    await _flushPending();
    if (previous != null) {
      await previous.disconnect();
    }
    return candidate;
  }

  Future<void> send(MessageEnvelope message) async {
    final transport = _active;
    if (transport == null) {
      _pending.add(message);
      return;
    }

    try {
      await transport.send(message);
    } catch (_) {
      _pending.add(message);
      rethrow;
    }
  }

  Future<void> dispose() async {
    final transport = _active;
    _active = null;
    if (transport != null) {
      await transport.disconnect();
    }
    await _changes.close();
  }

  Future<void> _flushPending() async {
    while (_pending.isNotEmpty && _active != null) {
      final message = _pending.removeAt(0);
      try {
        await _active!.send(message);
      } catch (_) {
        _pending.insert(0, message);
        rethrow;
      }
    }
  }
}
