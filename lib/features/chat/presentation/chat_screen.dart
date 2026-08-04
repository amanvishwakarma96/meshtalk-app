import 'package:flutter/material.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';

typedef SendMessage = Future<void> Function(String text);
typedef AsyncAction = Future<void> Function();
typedef UpdateDisplayName = Future<void> Function(String displayName);

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.state,
    required this.onSend,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onUpdateDisplayName,
    super.key,
  });

  final ChatSessionState state;
  final SendMessage onSend;
  final AsyncAction onRetry;
  final AsyncAction onOpenSettings;
  final UpdateDisplayName onUpdateDisplayName;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('MeshTalk'),
        actions: <Widget>[
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
          const _SecurityNotice(),
          _ConnectionCard(
            state: widget.state,
            onRetry: widget.onRetry,
            onOpenSettings: widget.onOpenSettings,
          ),
          Expanded(
            child: widget.state.messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nearby messages will appear here. Messages sent while scanning remain queued until a peer connects.',
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
                            ? 'Message nearby peers'
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
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(
      text: widget.state.profile.displayName,
    );
    final displayName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local profile'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                key: const ValueKey<String>('display-name-input'),
                controller: controller,
                autofocus: true,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  helperText: 'Shown to nearby MeshTalk peers',
                ),
                validator: (value) {
                  final normalized = value?.trim().replaceAll(
                        RegExp(r'\s+'),
                        ' ',
                      ) ??
                      '';
                  if (normalized.length < 2) {
                    return 'Enter at least 2 characters.';
                  }
                  if (normalized.length > 24) {
                    return 'Use no more than 24 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const Text('Device ID'),
              const SizedBox(height: 4),
              SelectableText(widget.state.profile.deviceId),
              const SizedBox(height: 12),
              const Text(
                'This identity and your message history stay on this device.',
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('save-profile-button'),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

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
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        'Not end-to-end encrypted yet. Do not send sensitive information.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
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
              Icon(_statusIcon(state.status)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _statusTitle(state.status),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(state.statusMessage),
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

  IconData _statusIcon(ChatConnectionStatus status) {
    return switch (status) {
      ChatConnectionStatus.initializing => Icons.hourglass_top,
      ChatConnectionStatus.permissionDenied => Icons.bluetooth_disabled,
      ChatConnectionStatus.bluetoothOff => Icons.bluetooth_disabled,
      ChatConnectionStatus.unsupported => Icons.phonelink_erase,
      ChatConnectionStatus.scanning => Icons.bluetooth_searching,
      ChatConnectionStatus.connected => Icons.bluetooth_connected,
      ChatConnectionStatus.error => Icons.error_outline,
    };
  }

  String _statusTitle(ChatConnectionStatus status) {
    return switch (status) {
      ChatConnectionStatus.initializing => 'Starting nearby chat',
      ChatConnectionStatus.permissionDenied => 'Bluetooth permission denied',
      ChatConnectionStatus.bluetoothOff => 'Bluetooth is off',
      ChatConnectionStatus.unsupported => 'BLE mesh unsupported',
      ChatConnectionStatus.scanning => 'Searching nearby',
      ChatConnectionStatus.connected => 'Nearby mesh connected',
      ChatConnectionStatus.error => 'Nearby chat error',
    };
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, super.key});

  final ChatTimelineMessage message;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.direction == ChatMessageDirection.outgoing;
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
}
