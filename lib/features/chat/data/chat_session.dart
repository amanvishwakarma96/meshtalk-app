import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/ble/mesh_relay_engine.dart';
import 'package:meshtalk_app/core/ble/message_envelope.dart';
import 'package:meshtalk_app/core/profile/local_profile.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';
import 'package:meshtalk_app/core/storage/message_store.dart';
import 'package:meshtalk_app/core/storage/stored_chat_message.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/core/transport/transport_manager.dart';
import 'package:meshtalk_app/core/transport/transport_runtime_diagnostics.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';
import 'package:meshtalk_app/features/chat/domain/transport_diagnostics.dart';
import 'package:uuid/uuid.dart';

typedef OpenAppSettings = Future<void> Function();

class ChatSession extends ChangeNotifier {
  ChatSession({
    required LocalProfile profile,
    required SecureRoom secureRoom,
    required BleMeshRadio radio,
    required ChatTransport bleTransport,
    required TransportManager transportManager,
    required MessageStore messageStore,
    required OpenAppSettings openAppSettings,
    MessageProtector? messageProtector,
    MeshRelayEngine? relayEngine,
    Uuid? uuid,
  })  : _secureRoom = secureRoom,
        _messageProtector = messageProtector ?? MessageProtector(),
        _radio = radio,
        _bleTransport = bleTransport,
        _transportManager = transportManager,
        _messageStore = messageStore,
        _openAppSettings = openAppSettings,
        _relayEngine = relayEngine ?? MeshRelayEngine(),
        _uuid = uuid ?? Uuid(),
        _state = ChatSessionState.initial(profile, secureRoom.summary);

  static const String _legacyRoomId = 'nearby';

  final SecureRoom _secureRoom;
  final MessageProtector _messageProtector;
  final BleMeshRadio _radio;
  final ChatTransport _bleTransport;
  final TransportManager _transportManager;
  final MessageStore _messageStore;
  final OpenAppSettings _openAppSettings;
  final MeshRelayEngine _relayEngine;
  final Uuid _uuid;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  final Map<String, List<NearbyPeer>> _peersByTransportId =
      <String, List<NearbyPeer>>{};
  final Map<String, PeerVerificationTransport> _verificationTransports =
      <String, PeerVerificationTransport>{};
  final Map<String, List<PeerVerificationRequest>>
      _verificationRequestsByTransportId =
      <String, List<PeerVerificationRequest>>{};

  ChatSessionState _state;
  bool _initialized = false;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _requestAuthorizationAgain = false;
  bool _closed = false;

  ChatSessionState get state => _state;

  Future<void> initialize() async {
    if (_initialized || _closed) {
      return;
    }
    _initialized = true;

    final secureHistory = await _messageStore.loadRoom(_secureRoom.id);
    final legacyHistory = _secureRoom.id == _legacyRoomId
        ? const <StoredChatMessage>[]
        : await _messageStore.loadRoom(_legacyRoomId);
    final pendingOutbound = await _preparePendingOutbound(
      await _messageStore.loadPendingOutbound(),
    );
    final historyById = <String, StoredChatMessage>{};
    for (final stored in <StoredChatMessage>[
      ...legacyHistory,
      ...secureHistory,
    ]) {
      historyById[stored.envelope.id] = stored;
    }
    final history = historyById.values.toList(growable: false)
      ..sort(
        (left, right) => left.envelope.timestampUtc.compareTo(
          right.envelope.timestampUtc,
        ),
      );

    for (final stored in history) {
      if (stored.direction == StoredMessageDirection.outgoing) {
        _relayEngine.markOriginated(stored.envelope.id);
      }
    }
    for (final stored in pendingOutbound) {
      _relayEngine.markOriginated(stored.envelope.id);
    }

    final timeline = <ChatTimelineMessage>[];
    for (final stored in history) {
      timeline.add(await _timelineFromStored(stored));
    }
    _replaceState(
      _state.copyWith(
        messages: List<ChatTimelineMessage>.unmodifiable(timeline),
        diagnostics: TransportDiagnosticsSnapshot.initial(_radio.availability),
      ),
    );

    _subscriptions.add(
      _radio.availabilityChanges.listen((_) {
        unawaited(_refreshTransport());
      }),
    );
    for (final transport in _transportManager.transports) {
      _peersByTransportId[transport.id] = const <NearbyPeer>[];
      _subscriptions
        ..add(
          transport.nearbyPeers.listen(
            (peers) => _handlePeersChanged(transport, peers),
          ),
        )
        ..add(transport.incomingMessages.listen(_handleIncomingMessage));

      if (transport is PeerVerificationTransport) {
        final verificationTransport = transport as PeerVerificationTransport;
        _verificationTransports[transport.id] = verificationTransport;
        _verificationRequestsByTransportId[transport.id] =
            verificationTransport.currentVerificationRequests;
        _subscriptions.add(
          verificationTransport.verificationRequests.listen(
            (requests) => _handleVerificationRequests(
              transport.id,
              requests,
            ),
          ),
        );
      }

      if (transport is TransportRuntimeDiagnostics) {
        final diagnosticsTransport = transport as TransportRuntimeDiagnostics;
        _subscriptions.add(
          diagnosticsTransport.runtimeErrors.listen(
            (error) => _handleRuntimeError(transport, error),
          ),
        );
      }
    }
    _subscriptions
      ..add(
        _transportManager.changes.listen(_handleActiveTransportChanged),
      )
      ..add(_transportManager.sentMessages.listen(_handleTransportSent));

    await _refreshTransport(requestAuthorization: true);
    _transportManager.restorePending(
      pendingOutbound.map((stored) => stored.envelope),
    );
    _syncPendingCount();
    if (_activePeers.isNotEmpty && _transportManager.pendingCount > 0) {
      await _flushQueuedMessages();
    }
  }

  Future<void> retry() async {
    await _refreshTransport(requestAuthorization: true);
  }

  Future<void> onAppResumed() async {
    await _refreshTransport();
  }

  Future<void> openSettings() => _openAppSettings();

  Future<void> approvePeer(PeerVerificationRequest request) async {
    final transport = _verificationTransports[request.transportId];
    if (transport == null) {
      throw StateError('The verification transport is no longer available.');
    }

    try {
      await transport.approvePeer(request.endpointId);
    } catch (error) {
      _recordTransportError(error);
      rethrow;
    }
  }

  Future<void> rejectPeer(PeerVerificationRequest request) async {
    final transport = _verificationTransports[request.transportId];
    if (transport == null) {
      return;
    }

    try {
      await transport.rejectPeer(request.endpointId);
    } catch (error) {
      _recordTransportError(error);
      rethrow;
    }
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _closed) {
      return;
    }

    final baseEnvelope = MessageEnvelope(
      id: _uuid.v4(),
      senderId: _state.profile.deviceId,
      roomId: _secureRoom.id,
      timestampUtc: DateTime.now().toUtc(),
      hopLimit: 4,
      payload: Uint8List(0),
    );
    final envelope = await _messageProtector.protect(
      envelope: baseEnvelope,
      clearText: Uint8List.fromList(utf8.encode(text)),
      room: _secureRoom,
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
          _timelineMessage(
            stored: stored,
            text: text,
            protectionStatus: MessageProtectionStatus.endToEndEncrypted,
          ),
        ],
      ),
    );

    try {
      await _transportManager.send(envelope);
    } catch (error) {
      _recordTransportError(error);
      // TransportManager keeps failed sends in memory while SQLite remains
      // the process-restart source of truth.
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

  void _handlePeersChanged(
    ChatTransport source,
    List<NearbyPeer> peers,
  ) {
    final normalized = List<NearbyPeer>.unmodifiable(peers);
    _peersByTransportId[source.id] = normalized;
    if (!identical(source, _transportManager.active)) {
      return;
    }

    _applyActiveTransportState(source, normalized);
    if (normalized.isNotEmpty && _transportManager.pendingCount > 0) {
      unawaited(_flushQueuedMessages());
    }
  }

  void _handleVerificationRequests(
    String transportId,
    List<PeerVerificationRequest> requests,
  ) {
    _verificationRequestsByTransportId[transportId] =
        List<PeerVerificationRequest>.unmodifiable(requests);
    final active = _transportManager.active;
    if (active == null || active.id != transportId) {
      return;
    }

    final activeRequests = _verificationRequestsFor(active.id);
    final statusMessage = activeRequests.isEmpty
        ? _searchingMessage(active, _transportManager.pendingCount)
        : _verificationMessage(activeRequests.length);
    _replaceState(
      _state.copyWith(
        statusMessage: _state.status == ChatConnectionStatus.scanning
            ? statusMessage
            : _state.statusMessage,
        verificationRequests: activeRequests,
        diagnostics: _diagnosticsForActive(active),
      ),
    );
  }

  void _handleRuntimeError(
    ChatTransport source,
    TransportRuntimeError error,
  ) {
    final active = _transportManager.active;
    if (active == null || active.id != source.id) {
      return;
    }

    _replaceState(
      _state.copyWith(
        statusMessage: error.message,
        diagnostics: _diagnosticsForActive(
          active,
          lastError: error.message,
        ),
      ),
    );
  }

  void _handleActiveTransportChanged(ChatTransport? active) {
    if (active == null) {
      return;
    }
    _applyActiveTransportState(
      active,
      _peersByTransportId[active.id] ?? const <NearbyPeer>[],
    );
  }

  void _handleIncomingMessage(MessageEnvelope envelope) {
    unawaited(_processIncomingMessage(envelope));
  }

  void _handleTransportSent(MessageEnvelope envelope) {
    unawaited(_markMessageSent(envelope.id));
  }

  Future<void> _processIncomingMessage(MessageEnvelope envelope) async {
    final decision = _relayEngine.processIncoming(envelope);
    if (decision.deliverLocally && envelope.roomId == _secureRoom.id) {
      await _deliverSecureMessage(envelope);
    }

    final relayEnvelope = decision.relayEnvelope;
    if (relayEnvelope != null) {
      await _relay(relayEnvelope);
    }
  }

  Future<void> _deliverSecureMessage(MessageEnvelope envelope) async {
    if (_state.messages.any((message) => message.id == envelope.id)) {
      return;
    }

    late final UnprotectedMessage unprotected;
    try {
      unprotected = await _messageProtector.unprotect(
        envelope: envelope,
        room: _secureRoom,
      );
    } on MessageProtectionException catch (error) {
      _recordProtectionError(error.message);
      return;
    }

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
      // Authenticated delivery remains visible if local persistence is down.
    }
    _replaceState(
      _state.copyWith(
        messages: <ChatTimelineMessage>[
          ..._state.messages,
          _timelineMessage(
            stored: stored,
            text: utf8.decode(unprotected.clearText, allowMalformed: true),
            protectionStatus: unprotected.status,
          ),
        ],
      ),
    );
  }

  Future<void> _relay(MessageEnvelope envelope) async {
    try {
      await _transportManager.send(envelope);
    } catch (error) {
      _recordTransportError(error);
      // Relay failures remain queued for the next active peer or transport.
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

  Future<List<StoredChatMessage>> _preparePendingOutbound(
    List<StoredChatMessage> storedMessages,
  ) async {
    final ready = <StoredChatMessage>[];
    for (final stored in storedMessages) {
      if (stored.direction != StoredMessageDirection.outgoing) {
        continue;
      }
      final envelope = stored.envelope;
      if (_messageProtector.isProtectedPayload(envelope.payload)) {
        if (envelope.roomId == _secureRoom.id) {
          ready.add(stored);
        }
        continue;
      }

      final baseEnvelope = envelope.copyWith(
        roomId: _secureRoom.id,
        payload: Uint8List(0),
      );
      final encryptedEnvelope = await _messageProtector.protect(
        envelope: baseEnvelope,
        clearText: envelope.payload,
        room: _secureRoom,
      );
      final migrated = StoredChatMessage(
        envelope: encryptedEnvelope,
        senderLabel: stored.senderLabel,
        direction: stored.direction,
        deliveryStatus: stored.deliveryStatus,
      );
      await _messageStore.upsert(migrated);
      ready.add(migrated);
    }
    return List<StoredChatMessage>.unmodifiable(ready);
  }

  Future<ChatTimelineMessage> _timelineFromStored(
    StoredChatMessage stored,
  ) async {
    try {
      final unprotected = await _messageProtector.unprotect(
        envelope: stored.envelope,
        room: _secureRoom,
        allowLegacy: true,
      );
      return _timelineMessage(
        stored: stored,
        text: utf8.decode(unprotected.clearText, allowMalformed: true),
        protectionStatus: unprotected.status,
      );
    } on MessageProtectionException {
      return _timelineMessage(
        stored: stored,
        text:
            'Encrypted message could not be authenticated with this room key.',
        protectionStatus: MessageProtectionStatus.unableToDecrypt,
      );
    }
  }

  ChatTimelineMessage _timelineMessage({
    required StoredChatMessage stored,
    required String text,
    required MessageProtectionStatus protectionStatus,
  }) {
    return ChatTimelineMessage(
      id: stored.envelope.id,
      text: text,
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
      protectionStatus: protectionStatus,
    );
  }

  Future<void> _refreshTransport({bool requestAuthorization = false}) async {
    if (_closed) {
      return;
    }
    if (_refreshing) {
      _refreshAgain = true;
      _requestAuthorizationAgain =
          _requestAuthorizationAgain || requestAuthorization;
      return;
    }

    _refreshing = true;
    var authorize = requestAuthorization;
    try {
      do {
        _refreshAgain = false;
        await _refreshTransportOnce(requestAuthorization: authorize);
        authorize = _requestAuthorizationAgain;
        _requestAuthorizationAgain = false;
      } while (_refreshAgain && !_closed);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshTransportOnce({
    required bool requestAuthorization,
  }) async {
    try {
      if (requestAuthorization &&
          _radio.availability == BleRadioAvailability.unauthorized) {
        try {
          await _bleTransport.connect();
        } catch (_) {
          // TransportManager will continue to a platform local-network
          // fallback when the BLE path remains unavailable.
        }
      }

      final active = await _transportManager.refresh();
      if (active == null) {
        _applyNoTransportState(_radio.availability);
        return;
      }

      _applyActiveTransportState(
        active,
        _peersByTransportId[active.id] ?? const <NearbyPeer>[],
        clearLastError: true,
      );
    } on TransportActivationException catch (error) {
      if (error.kind == TransportKind.localWifi &&
          error.failure == TransportActivationFailure.permissionDenied) {
        _replaceState(
          _state.copyWith(
            status: ChatConnectionStatus.localNetworkPermissionDenied,
            statusMessage: error.message,
            peers: const <NearbyPeer>[],
            pendingCount: _transportManager.pendingCount,
            verificationRequests: const <PeerVerificationRequest>[],
            diagnostics: _diagnosticsWithoutActive(error.message),
            clearActiveTransport: true,
          ),
        );
      } else {
        _replaceState(
          _state.copyWith(
            status: ChatConnectionStatus.error,
            statusMessage: error.message,
            peers: const <NearbyPeer>[],
            pendingCount: _transportManager.pendingCount,
            verificationRequests: const <PeerVerificationRequest>[],
            diagnostics: _diagnosticsWithoutActive(error.message),
            clearActiveTransport: true,
          ),
        );
      }
    } catch (error) {
      final active = _transportManager.active;
      if (active != null) {
        _applyActiveTransportState(
          active,
          _peersByTransportId[active.id] ?? const <NearbyPeer>[],
          lastError: error.toString(),
        );
      } else {
        _applyNoTransportState(
          _radio.availability,
          lastError: error.toString(),
        );
      }
    }
  }

  Future<void> _flushQueuedMessages() async {
    try {
      await _transportManager.refresh();
    } catch (error) {
      _recordTransportError(error);
      // Pending entries remain in both TransportManager and SQLite.
    }
    _syncPendingCount();
  }

  void _applyActiveTransportState(
    ChatTransport transport,
    List<NearbyPeer> peers, {
    String? lastError,
    bool clearLastError = false,
  }) {
    final connected = peers.isNotEmpty;
    final verificationRequests = _verificationRequestsFor(transport.id);
    final status = connected
        ? ChatConnectionStatus.connected
        : ChatConnectionStatus.scanning;
    final statusMessage = connected
        ? _connectedMessage(transport, peers.length)
        : verificationRequests.isNotEmpty
            ? _verificationMessage(verificationRequests.length)
            : _searchingMessage(transport, _transportManager.pendingCount);
    _replaceState(
      _state.copyWith(
        status: status,
        statusMessage: statusMessage,
        peers: List<NearbyPeer>.unmodifiable(peers),
        pendingCount: _transportManager.pendingCount,
        activeTransportKind: transport.kind,
        verificationRequests: verificationRequests,
        diagnostics: _diagnosticsForActive(
          transport,
          lastError: lastError,
          clearLastError: clearLastError,
        ),
      ),
    );
  }

  void _applyNoTransportState(
    BleRadioAvailability availability, {
    String? lastError,
  }) {
    final (status, message) = switch (availability) {
      BleRadioAvailability.unsupported => (
          ChatConnectionStatus.unsupported,
          'Required BLE roles are unsupported and no local fallback is active.',
        ),
      BleRadioAvailability.unauthorized => (
          ChatConnectionStatus.permissionDenied,
          'Bluetooth permission is required and no local fallback is active.',
        ),
      BleRadioAvailability.poweredOff => (
          ChatConnectionStatus.bluetoothOff,
          'Bluetooth is off and no local-network fallback is active.',
        ),
      BleRadioAvailability.ready => (
          ChatConnectionStatus.error,
          'No nearby transport could start. Try again.',
        ),
    };
    _replaceState(
      _state.copyWith(
        status: status,
        statusMessage: message,
        peers: const <NearbyPeer>[],
        pendingCount: _transportManager.pendingCount,
        verificationRequests: const <PeerVerificationRequest>[],
        diagnostics: _diagnosticsWithoutActive(lastError),
        clearActiveTransport: true,
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
    final active = _transportManager.active;
    final statusMessage =
        _state.status == ChatConnectionStatus.scanning && active != null
            ? _state.verificationRequests.isNotEmpty
                ? _verificationMessage(_state.verificationRequests.length)
                : _searchingMessage(active, pendingCount)
            : _state.statusMessage;
    _replaceState(
      _state.copyWith(
        pendingCount: pendingCount,
        statusMessage: statusMessage,
      ),
    );
  }

  void _recordTransportError(Object error) {
    final active = _transportManager.active;
    final diagnostics = active == null
        ? _diagnosticsWithoutActive(error.toString())
        : _diagnosticsForActive(active, lastError: error.toString());
    _replaceState(_state.copyWith(diagnostics: diagnostics));
  }

  void _recordProtectionError(String message) {
    final active = _transportManager.active;
    final diagnostics = active == null
        ? _diagnosticsWithoutActive(message)
        : _diagnosticsForActive(active, lastError: message);
    _replaceState(_state.copyWith(diagnostics: diagnostics));
  }

  List<NearbyPeer> get _activePeers {
    final active = _transportManager.active;
    if (active == null) {
      return const <NearbyPeer>[];
    }
    return _peersByTransportId[active.id] ?? const <NearbyPeer>[];
  }

  List<PeerVerificationRequest> _verificationRequestsFor(
    String transportId,
  ) {
    return _verificationRequestsByTransportId[transportId] ??
        const <PeerVerificationRequest>[];
  }

  TransportDiagnosticsSnapshot _diagnosticsForActive(
    ChatTransport transport, {
    String? lastError,
    bool clearLastError = false,
  }) {
    final previousError = _state.diagnostics?.lastError;
    return TransportDiagnosticsSnapshot(
      bluetoothAvailability: _radio.availability,
      refreshedAtUtc: DateTime.now().toUtc(),
      activeTransportId: transport.id,
      activeTransportKind: transport.kind,
      activeTransportMaxPayloadBytes: transport.capabilities.maxPayloadBytes,
      lastError: clearLastError ? null : lastError ?? previousError,
    );
  }

  TransportDiagnosticsSnapshot _diagnosticsWithoutActive(
    String? lastError,
  ) {
    return TransportDiagnosticsSnapshot(
      bluetoothAvailability: _radio.availability,
      refreshedAtUtc: DateTime.now().toUtc(),
      lastError: lastError ?? _state.diagnostics?.lastError,
    );
  }

  String _searchingMessage(ChatTransport transport, int pendingCount) {
    final suffix = pendingCount == 0
        ? ''
        : ' $pendingCount message${pendingCount == 1 ? '' : 's'} queued.';
    return switch (transport.kind) {
      TransportKind.bleMesh =>
        'Searching for encrypted room peers over BLE…$suffix',
      TransportKind.localWifi =>
        'BLE unavailable. Searching with ${_localTransportName(transport)}…$suffix',
      TransportKind.internetRelay => 'Searching for an internet relay…$suffix',
    };
  }

  String _verificationMessage(int count) {
    return '$count nearby peer${count == 1 ? '' : 's'} waiting for code verification.';
  }

  String _connectedMessage(ChatTransport transport, int peerCount) {
    final peerLabel = '$peerCount nearby peer${peerCount == 1 ? '' : 's'}';
    return switch (transport.kind) {
      TransportKind.bleMesh => 'Connected to $peerLabel over BLE.',
      TransportKind.localWifi =>
        'Connected to $peerLabel over verified ${_localTransportName(transport)}.',
      TransportKind.internetRelay =>
        'Connected to $peerLabel through an internet relay.',
    };
  }

  String _localTransportName(ChatTransport transport) {
    return switch (transport.id) {
      'android-nearby' => 'Android Nearby Connections',
      'ios-multipeer' => 'iOS Multipeer Connectivity',
      _ => 'local-network fallback',
    };
  }

  void _replaceState(ChatSessionState nextState) {
    if (_closed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }
}
