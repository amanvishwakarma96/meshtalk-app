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
  final StreamController<MessageEnvelope> _sentMessages =
      StreamController<MessageEnvelope>.broadcast();

  ChatTransport? _active;

  List<ChatTransport> get transports => _transports;
  ChatTransport? get active => _active;
  int get pendingCount => _pending.length;
  Stream<ChatTransport?> get changes => _changes.stream;
  Stream<MessageEnvelope> get sentMessages => _sentMessages.stream;

  void restorePending(Iterable<MessageEnvelope> messages) {
    for (final message in messages) {
      _queue(message);
    }
  }

  Future<ChatTransport?> refresh() async {
    ChatTransport? candidate;
    Object? lastActivationError;

    for (final transport in _transports) {
      if (!await transport.isAvailable()) {
        continue;
      }
      if (identical(transport, _active)) {
        candidate = transport;
        break;
      }

      try {
        await transport.connect();
        candidate = transport;
        break;
      } catch (error) {
        lastActivationError = error;
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
      if (lastActivationError != null) {
        Error.throwWithStackTrace(
          lastActivationError,
          StackTrace.current,
        );
      }
      return null;
    }

    _active = candidate;
    _changes.add(candidate);
    if (previous != null) {
      await previous.disconnect();
    }
    await _flushPending();
    return candidate;
  }

  Future<void> send(MessageEnvelope message) async {
    final transport = _active;
    if (transport == null) {
      _queue(message);
      return;
    }

    try {
      await transport.send(message);
      _sentMessages.add(message);
    } catch (_) {
      _queue(message);
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
    await _sentMessages.close();
  }

  Future<void> _flushPending() async {
    while (_pending.isNotEmpty && _active != null) {
      final message = _pending.removeAt(0);
      try {
        await _active!.send(message);
        _sentMessages.add(message);
      } catch (_) {
        _pending.insert(0, message);
        rethrow;
      }
    }
  }

  void _queue(MessageEnvelope message) {
    if (_pending.any((pending) => pending.id == message.id)) {
      return;
    }
    _pending.add(message);
  }
}
