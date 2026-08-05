import 'package:flutter/material.dart';
import 'package:meshtalk_app/core/security/message_protector.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/core/transport/peer_verification.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';
import 'package:meshtalk_app/features/chat/presentation/profile_dialog.dart';
import 'package:meshtalk_app/features/chat/presentation/secure_room_dialog.dart';
import 'package:meshtalk_app/features/chat/presentation/transport_diagnostics_dialog.dart';

typedef SendMessage = Future<void> Function(String text);
typedef AsyncAction = Future<void> Function();
typedef UpdateDisplayName = Future<void> Function(String displayName);
typedef PeerVerificationAction = Future<void> Function(
  PeerVerificationRequest request,
);

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.state,
    required this.onSend,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onUpdateDisplayName,
    required this.onApprovePeer,
    required this.onRejectPeer,
    required this.onExportRoomCode,
    required this.onCreateRoom,
    required this.onJoinRoom,
    super.key,
  });

  final ChatSessionState state;
  final SendMessage onSend;
  final AsyncAction onRetry;
  final AsyncAction onOpenSettings;
  final UpdateDisplayName onUpdateDisplayName;
  final PeerVerificationAction onApprovePeer;
  final PeerVerificationAction onRejectPeer;
  final ExportSecureRoomCode onExportRoomCode;
  final CreateSecureRoom onCreateRoom;
  final JoinSecureRoom onJoinRoom;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.state.canSend || _sending) {
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      if (mounted) {
        _controller.clear();
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final verificationRequests = widget.state.verificationRequests;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MeshTalk'),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('secure-room-button'),
            onPressed: _showSecureRoom,
            tooltip: 'Encrypted room',
            icon: const Icon(Icons.lock_outline),
          ),
          IconButton(
            key: const ValueKey<String>('diagnostics-button'),
            onPressed: _showDiagnostics,
            tooltip: 'Transport diagnostics',
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          IconButton(
            key: const ValueKey<String>('profile-button'),
            onPressed: _showProfile,
            tooltip: 'Local profile',
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.state.statusMessage,
              key: const ValueKey<String>('transport-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          _SecurityNotice(state: widget.state),
          _ConnectionCard(
            state: widget.state,
            onRetry: widget.onRetry,
            onOpenSettings: widget.onOpenSettings,
          ),
          if (verificationRequests.isNotEmpty)
            _PeerVerificationCard(
              request: verificationRequests.first,
              additionalRequestCount: verificationRequests.length - 1,
              onApprove: widget.onApprovePeer,
              onReject: widget.onRejectPeer,
            ),
          Expanded(
            child: widget.state.messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Encrypted nearby messages will appear here. Messages sent while scanning remain queued until a peer connects.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: widget.state.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.state.messages[index];
                      return _MessageTile(
                        key: ValueKey<String>('message-${message.id}'),
                        message: message,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('message-input'),
                      controller: _controller,
                      enabled: widget.state.canSend && !_sending,
                      decoration: InputDecoration(
                        hintText: widget.state.canSend
                            ? 'Message encrypted room peers'
                            : 'Nearby chat unavailable',
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const ValueKey<String>('send-button'),
                    onPressed: widget.state.canSend && !_sending ? _send : null,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProfile() async {
    final displayName = await showDialog<String>(
      context: context,
      builder: (context) => ProfileDialog(profile: widget.state.profile),
    );

    if (displayName == null ||
        displayName == widget.state.profile.displayName ||
        !mounted) {
      return;
    }

    try {
      await widget.onUpdateDisplayName(displayName);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the display name.')),
        );
      }
    }
  }

  Future<void> _showSecureRoom() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SecureRoomDialog(
        room: widget.state.secureRoom,
        onExportCode: widget.onExportRoomCode,
        onCreateRoom: widget.onCreateRoom,
        onJoinRoom: widget.onJoinRoom,
      ),
    );
  }

  Future<void> _showDiagnostics() async {
    await showDialog<void>(
      context: context,
      builder: (context) => TransportDiagnosticsDialog(
        state: widget.state,
        onRefresh: widget.onRetry,
      ),
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice({required this.state});

  final ChatSessionState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.lock,
            size: 16,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${state.secureRoom.name} · ${state.secureRoom.fingerprint} · End-to-end encrypted',
              key: const ValueKey<String>('e2ee-room-notice'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.state,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final ChatSessionState state;
  final AsyncAction onRetry;
  final AsyncAction onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final action = state.canOpenSettings
        ? FilledButton.tonalIcon(
            key: const ValueKey<String>('open-settings-button'),
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings),
            label: const Text('Open settings'),
          )
        : state.canRetry
            ? FilledButton.tonalIcon(
                key: const ValueKey<String>('retry-button'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              )
            : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Icon(_statusIcon(state)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _statusTitle(state),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(state.statusMessage),
                    if (state.activeTransportKind == TransportKind.localWifi &&
                        state.status == ChatConnectionStatus.connected)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Peer verified using the matching ${_localTransportName(state)} code.',
                          key: const ValueKey<String>('nearby-verified-label'),
                        ),
                      ),
                    if (state.pendingCount > 0) ...<Widget>[
                      const SizedBox(height: 4),
                      Text('${state.pendingCount} queued'),
                    ],
                  ],
                ),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(width: 8),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(ChatSessionState state) {
    return switch (state.status) {
      ChatConnectionStatus.initializing => Icons.hourglass_top,
      ChatConnectionStatus.permissionDenied => Icons.bluetooth_disabled,
      ChatConnectionStatus.localNetworkPermissionDenied => Icons.wifi_off,
      ChatConnectionStatus.bluetoothOff => Icons.bluetooth_disabled,
      ChatConnectionStatus.unsupported => Icons.phonelink_erase,
      ChatConnectionStatus.scanning => state.verificationRequests.isNotEmpty
          ? Icons.verified_user_outlined
          : state.activeTransportKind == TransportKind.localWifi
              ? Icons.wifi_find
              : Icons.bluetooth_searching,
      ChatConnectionStatus.connected =>
        state.activeTransportKind == TransportKind.localWifi
            ? Icons.verified_user
            : Icons.bluetooth_connected,
      ChatConnectionStatus.error => Icons.error_outline,
    };
  }

  String _statusTitle(ChatSessionState state) {
    return switch (state.status) {
      ChatConnectionStatus.initializing => 'Starting encrypted nearby chat',
      ChatConnectionStatus.permissionDenied => 'Bluetooth permission denied',
      ChatConnectionStatus.localNetworkPermissionDenied =>
        'Nearby permission denied',
      ChatConnectionStatus.bluetoothOff => 'Bluetooth is off',
      ChatConnectionStatus.unsupported => 'Nearby transport unsupported',
      ChatConnectionStatus.scanning => state.verificationRequests.isNotEmpty
          ? 'Verify Nearby peer'
          : state.activeTransportKind == TransportKind.localWifi
              ? 'Searching with ${_localTransportName(state)}'
              : 'Searching nearby over BLE',
      ChatConnectionStatus.connected =>
        state.activeTransportKind == TransportKind.localWifi
            ? 'Verified ${_localTransportName(state)} connection'
            : 'Nearby BLE connected',
      ChatConnectionStatus.error => 'Nearby chat error',
    };
  }

  String _localTransportName(ChatSessionState state) {
    return switch (state.diagnostics?.activeTransportId) {
      'android-nearby' => 'Android Nearby',
      'ios-multipeer' => 'iOS Multipeer',
      _ => 'local-network',
    };
  }
}

class _PeerVerificationCard extends StatefulWidget {
  const _PeerVerificationCard({
    required this.request,
    required this.additionalRequestCount,
    required this.onApprove,
    required this.onReject,
  });

  final PeerVerificationRequest request;
  final int additionalRequestCount;
  final PeerVerificationAction onApprove;
  final PeerVerificationAction onReject;

  @override
  State<_PeerVerificationCard> createState() => _PeerVerificationCardState();
}

class _PeerVerificationCardState extends State<_PeerVerificationCard> {
  bool _working = false;

  Future<void> _run(PeerVerificationAction action) async {
    if (_working) {
      return;
    }
    setState(() => _working = true);
    try {
      await action(widget.request);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The peer verification request is no longer active.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        key: ValueKey<String>('peer-verification-${request.endpointId}'),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Verify ${request.displayName}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Confirm only when the same code appears on the other phone.',
              ),
              const SizedBox(height: 8),
              SelectableText(
                request.authenticationToken,
                key: const ValueKey<String>('verification-code'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
              ),
              if (widget.additionalRequestCount > 0) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  '${widget.additionalRequestCount} more peer verification request${widget.additionalRequestCount == 1 ? '' : 's'} waiting.',
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    key: ValueKey<String>(
                      'reject-peer-${request.endpointId}',
                    ),
                    onPressed: _working ? null : () => _run(widget.onReject),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: ValueKey<String>(
                      'approve-peer-${request.endpointId}',
                    ),
                    onPressed: _working ? null : () => _run(widget.onApprove),
                    icon: _working
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user),
                    label: const Text('Codes match'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, super.key});

  final ChatTimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.direction == ChatMessageDirection.outgoing;
    final protection = _protectionLabel(message.protectionStatus);
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment:
                  outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message.text,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${message.senderLabel} · ${_timeLabel(message.timestampUtc)} · ${_deliveryLabel(message.deliveryStatus)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(protection.$1, size: 13),
                    const SizedBox(width: 3),
                    Text(
                      protection.$2,
                      key: ValueKey<String>('message-protection-${message.id}'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _timeLabel(DateTime timestampUtc) {
    final local = timestampUtc.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _deliveryLabel(ChatDeliveryStatus status) {
    return switch (status) {
      ChatDeliveryStatus.queued => 'queued',
      ChatDeliveryStatus.sent => 'sent',
      ChatDeliveryStatus.received => 'received',
    };
  }

  (IconData, String) _protectionLabel(MessageProtectionStatus status) {
    return switch (status) {
      MessageProtectionStatus.endToEndEncrypted => (
          Icons.lock,
          'end-to-end encrypted',
        ),
      MessageProtectionStatus.legacyUnencrypted => (
          Icons.warning_amber,
          'legacy unencrypted history',
        ),
      MessageProtectionStatus.unableToDecrypt => (
          Icons.lock_reset,
          'unable to authenticate',
        ),
    };
  }
}
