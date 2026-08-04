import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/mesh_relay_engine.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/storage/message_store.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';
import 'package:uuid/uuid.dart';

typedef OpenAppSettings = Future<void> Function();

class ChatSession extends ChangeNotifier {
  ChatSession({
    required LocalProfile profile,
    required BleMeshRadio radio,
    required ChatTransport bleTransport,
    required TransportManager transportManager,
    required MessageStore messageStore,
    required OpenAppSettings openAppSettings,
    MeshRelayEngine? relayEngine,
    Uuid? uuid,
  })  : _radio = radio,
        _bleTransport = bleTransport,
        _transportManager = transportManager,
        _messageStore = messageStore,
        _openAppSettings = openAppSettings,
        _relayEngine = relayEngine ?? MeshRelayEngine(),
        _uuid = uuid ?? Uuid(),
        _state = ChatSessionState.initial(profile);

  static const String _roomId = 'nearby';

  final BleMeshRadio _radio;
  final ChatTransport _bleTransport;
  final TransportManager _transportManager;
  final MessageStore _messageStore;
  final OpenAppSettings _openAppSettings;
  final MeshRelayEngine _relayEngine;
  final Uuid _uuid;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  ChatSessionState _state;
  bool _initialized = false;
  bool _refreshing = false;
  bool _closed = false;

  ChatSessionState get state => _state;

  Future<void> initialize() async {
    if (_initialized || _closed) {
      return;
    }
    _initialized = true;

    final history = await _messageStore.loadRoom(_roomId);
    final pendingOutbound = await _messageStore.loadPendingOutbound();
    for (final stored in history) {
      if (stored.direction == StoredMessageDirection.outgoing) {
        _relayEngine.markOriginated(stored.envelope.id);
      }
    }
    for (final stored in pendingOutbound) {
      _relayEngine.markOriginated(stored.envelope.id);
    }

    _replaceState(
      _state.copyWith(
        messages: history.map(_toTimelineMessage).toList(growable: false),
      ),
    );

    _subscriptions
      ..add(_radio.availabilityChanges.listen(_handleAvailabilityChanged))
      ..add(_bleTransport.nearbyPeers.listen(_handlePeersChanged))
      ..add(_bleTransport.incomingMessages.listen(_handleIncomingMessage))
      ..add(_transportManager.sentMessages.listen(_handleTransportSent));

    await _refreshTransport(requestAuthorization: true);
    _transportManager.restorePending(
      pendingOutbound.map((stored) => stored.envelope),
    );
    _syncPendingCount();
    if (_state.peers.isNotEmpty && _transportManager.pendingCount > 0) {
      await _flushQueuedMessages();
    }
  }

  Future<void> retry() async {
    await _refreshTransport(requestAuthorization: true);
  }

  Future<void> openSettings() => _openAppSettings();

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _closed) {
      return;
    }

    final envelope = MessageEnvelope(
      id: _uuid.v4(),
      senderId: _state.profile.deviceId,
      roomId: _roomId,
      timestampUtc: DateTime.now().toUtc(),
      hopLimit: 4,
      payload: Uint8List.fromList(utf8.encode(text)),
    );
    _relayEngine.markOriginated(envelope.id);

    final stored = StoredChatMessage(
      envelope: envelope,
      senderLabel: _state.profile.displayName,
      direction: StoredMessageDirection.outgoing,
      deliveryStatus: StoredDeliveryStatus.queued,
    );
    await _messageStore.upsert(stored);
    _replaceState(
      _state.copyWith(
        messages: <ChatTimelineMessage>[
          ..._state.messages,
          _toTimelineMessage(stored),
        ],
      ),
    );

    try {
      await _transportManager.send(envelope);
    } catch (_) {
      // The transport manager keeps failed sends in its in-memory queue while
      // SQLite remains the process-restart source of truth.
    }
    _syncPendingCount();
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    final subscriptions = _subscriptions.toList(growable: false);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await _transportManager.dispose();
    super.dispose();
  }

  void _handleAvailabilityChanged(BleRadioAvailability availability) {
    unawaited(_refreshTransport());
  }

  void _handlePeersChanged(List<NearbyPeer> peers) {
    final status = peers.isEmpty
        ? ChatConnectionStatus.scanning
        : ChatConnectionStatus.connected;
    final message = peers.isEmpty
        ? _scanningMessage(_transportManager.pendingCount)
        : 'Connected to ${peers.length} nearby peer${peers.length == 1 ? '' : 's'} over BLE.';
    _replaceState(
      _state.copyWith(
        status: status,
        statusMessage: message,
        peers: List<NearbyPeer>.unmodifiable(peers),
        pendingCount: _transportManager.pendingCount,
      ),
    );

    if (peers.isNotEmpty && _transportManager.pendingCount > 0) {
      unawaited(_flushQueuedMessages());
    }
  }

  void _handleIncomingMessage(MessageEnvelope envelope) {
    unawaited(_processIncomingMessage(envelope));
  }

  void _handleTransportSent(MessageEnvelope envelope) {
    unawaited(_markMessageSent(envelope.id));
  }

  Future<void> _processIncomingMessage(MessageEnvelope envelope) async {
    final decision = _relayEngine.processIncoming(envelope);
    if (decision.deliverLocally) {
      final senderSuffix = envelope.senderId.length <= 6
          ? envelope.senderId
          : envelope.senderId.substring(0, 6);
      final stored = StoredChatMessage(
        envelope: envelope,
        senderLabel: 'Peer $senderSuffix',
        direction: StoredMessageDirection.incoming,
        deliveryStatus: StoredDeliveryStatus.received,
      );
      try {
        await _messageStore.upsert(stored);
      } catch (_) {
        // Delivery remains visible even if local persistence is unavailable.
      }
      _replaceState(
        _state.copyWith(
          messages: <ChatTimelineMessage>[
            ..._state.messages,
            _toTimelineMessage(stored),
          ],
        ),
      );
    }

    final relayEnvelope = decision.relayEnvelope;
    if (relayEnvelope != null) {
      await _relay(relayEnvelope);
    }
  }

  Future<void> _relay(MessageEnvelope envelope) async {
    try {
      await _transportManager.send(envelope);
    } catch (_) {
      // Relay failures remain queued by TransportManager for the next peer.
    }
    _syncPendingCount();
  }

  Future<void> _markMessageSent(String messageId) async {
    try {
      await _messageStore.markSent(messageId);
    } finally {
      _updateDelivery(messageId, ChatDeliveryStatus.sent);
      _syncPendingCount();
    }
  }

  Future<void> _refreshTransport({bool requestAuthorization = false}) async {
    if (_refreshing || _closed) {
      return;
    }
    _refreshing = true;
    try {
      if (requestAuthorization &&
          _radio.availability == BleRadioAvailability.unauthorized) {
        try {
          await _bleTransport.connect();
        } catch (_) {
          // The resulting radio state is mapped below.
        }
      }

      final availability = _radio.availability;
      if (availability != BleRadioAvailability.ready) {
        await _transportManager.refresh();
        _applyUnavailableState(availability);
        return;
      }

      final active = await _transportManager.refresh();
      if (active == null) {
        _replaceState(
          _state.copyWith(
            status: ChatConnectionStatus.error,
            statusMessage:
                'BLE is available, but the transport could not start.',
          ),
        );
        return;
      }

      final peers = _state.peers;
      _replaceState(
        _state.copyWith(
          status: peers.isEmpty
              ? ChatConnectionStatus.scanning
              : ChatConnectionStatus.connected,
          statusMessage: peers.isEmpty
              ? _scanningMessage(_transportManager.pendingCount)
              : 'Connected to ${peers.length} nearby peer${peers.length == 1 ? '' : 's'} over BLE.',
          pendingCount: _transportManager.pendingCount,
        ),
      );
    } catch (_) {
      _applyUnavailableState(_radio.availability);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _flushQueuedMessages() async {
    try {
      await _transportManager.refresh();
    } catch (_) {
      // Pending entries remain in both TransportManager and SQLite.
    }
    _syncPendingCount();
  }

  void _applyUnavailableState(BleRadioAvailability availability) {
    final (status, message) = switch (availability) {
      BleRadioAvailability.unsupported => (
          ChatConnectionStatus.unsupported,
          'This device does not support the required Bluetooth LE roles.',
        ),
      BleRadioAvailability.unauthorized => (
          ChatConnectionStatus.permissionDenied,
          'Bluetooth permission is required for nearby mesh chat.',
        ),
      BleRadioAvailability.poweredOff => (
          ChatConnectionStatus.bluetoothOff,
          'Turn on Bluetooth, then retry nearby chat.',
        ),
      BleRadioAvailability.ready => (
          ChatConnectionStatus.error,
          'Unable to start nearby chat. Try again.',
        ),
    };
    _replaceState(
      _state.copyWith(
        status: status,
        statusMessage: message,
        peers: const <NearbyPeer>[],
        pendingCount: _transportManager.pendingCount,
      ),
    );
  }

  void _updateDelivery(String messageId, ChatDeliveryStatus deliveryStatus) {
    final messages = _state.messages
        .map(
          (message) => message.id == messageId
              ? message.copyWith(deliveryStatus: deliveryStatus)
              : message,
        )
        .toList(growable: false);
    _replaceState(_state.copyWith(messages: messages));
  }

  void _syncPendingCount() {
    final pendingCount = _transportManager.pendingCount;
    final statusMessage = _state.status == ChatConnectionStatus.scanning
        ? _scanningMessage(pendingCount)
        : _state.statusMessage;
    _replaceState(
      _state.copyWith(
        pendingCount: pendingCount,
        statusMessage: statusMessage,
      ),
    );
  }

  ChatTimelineMessage _toTimelineMessage(StoredChatMessage stored) {
    return ChatTimelineMessage(
      id: stored.envelope.id,
      text: utf8.decode(stored.envelope.payload, allowMalformed: true),
      senderLabel: stored.senderLabel,
      timestampUtc: stored.envelope.timestampUtc,
      direction: switch (stored.direction) {
        StoredMessageDirection.outgoing => ChatMessageDirection.outgoing,
        StoredMessageDirection.incoming => ChatMessageDirection.incoming,
      },
      deliveryStatus: switch (stored.deliveryStatus) {
        StoredDeliveryStatus.queued => ChatDeliveryStatus.queued,
        StoredDeliveryStatus.sent => ChatDeliveryStatus.sent,
        StoredDeliveryStatus.received => ChatDeliveryStatus.received,
      },
    );
  }

  String _scanningMessage(int pendingCount) {
    if (pendingCount == 0) {
      return 'Searching for nearby MeshTalk peers…';
    }
    return 'Searching for peers… $pendingCount message${pendingCount == 1 ? '' : 's'} queued.';
  }

  void _replaceState(ChatSessionState nextState) {
    if (_closed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }
}
