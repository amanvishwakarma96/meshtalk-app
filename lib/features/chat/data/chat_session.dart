import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/mesh_relay_engine.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
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
    required OpenAppSettings openAppSettings,
    MeshRelayEngine? relayEngine,
    Uuid? uuid,
  })  : _radio = radio,
        _bleTransport = bleTransport,
        _transportManager = transportManager,
        _openAppSettings = openAppSettings,
        _relayEngine = relayEngine ?? MeshRelayEngine(),
        _uuid = uuid ?? Uuid(),
        _state = ChatSessionState.initial(profile);

  final BleMeshRadio _radio;
  final ChatTransport _bleTransport;
  final TransportManager _transportManager;
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

    _subscriptions
      ..add(_radio.availabilityChanges.listen(_handleAvailabilityChanged))
      ..add(_bleTransport.nearbyPeers.listen(_handlePeersChanged))
      ..add(_bleTransport.incomingMessages.listen(_handleIncomingMessage));

    await _refreshTransport(requestAuthorization: true);
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
      roomId: 'nearby',
      timestampUtc: DateTime.now().toUtc(),
      hopLimit: 4,
      payload: Uint8List.fromList(utf8.encode(text)),
    );
    _relayEngine.markOriginated(envelope.id);

    final timelineMessage = ChatTimelineMessage(
      id: envelope.id,
      text: text,
      senderLabel: _state.profile.displayName,
      timestampUtc: envelope.timestampUtc,
      direction: ChatMessageDirection.outgoing,
      deliveryStatus: ChatDeliveryStatus.queued,
    );
    _replaceState(
      _state.copyWith(
        messages: <ChatTimelineMessage>[
          ..._state.messages,
          timelineMessage,
        ],
      ),
    );

    try {
      await _transportManager.send(envelope);
      final deliveryStatus = _transportManager.pendingCount == 0
          ? ChatDeliveryStatus.sent
          : ChatDeliveryStatus.queued;
      _updateDelivery(envelope.id, deliveryStatus);
    } catch (_) {
      _updateDelivery(envelope.id, ChatDeliveryStatus.queued);
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
    final decision = _relayEngine.processIncoming(envelope);
    if (decision.deliverLocally) {
      final senderSuffix = envelope.senderId.length <= 6
          ? envelope.senderId
          : envelope.senderId.substring(0, 6);
      final message = ChatTimelineMessage(
        id: envelope.id,
        text: utf8.decode(envelope.payload, allowMalformed: true),
        senderLabel: 'Peer $senderSuffix',
        timestampUtc: envelope.timestampUtc,
        direction: ChatMessageDirection.incoming,
        deliveryStatus: ChatDeliveryStatus.received,
      );
      _replaceState(
        _state.copyWith(
          messages: <ChatTimelineMessage>[..._state.messages, message],
        ),
      );
    }

    final relayEnvelope = decision.relayEnvelope;
    if (relayEnvelope != null) {
      unawaited(_relay(relayEnvelope));
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
            statusMessage: 'BLE is available, but the transport could not start.',
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
      if (_transportManager.pendingCount == 0) {
        final messages = _state.messages
            .map(
              (message) => message.direction == ChatMessageDirection.outgoing &&
                      message.deliveryStatus == ChatDeliveryStatus.queued
                  ? message.copyWith(deliveryStatus: ChatDeliveryStatus.sent)
                  : message,
            )
            .toList(growable: false);
        _replaceState(
          _state.copyWith(
            messages: messages,
            pendingCount: 0,
          ),
        );
      }
    } catch (_) {
      _syncPendingCount();
    }
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
