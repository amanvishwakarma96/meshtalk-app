import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';

typedef ExportSecureRoomCode = Future<String> Function();
typedef CreateSecureRoom = Future<void> Function(String name);
typedef JoinSecureRoom = Future<void> Function(String code);

class SecureRoomDialog extends StatefulWidget {
  const SecureRoomDialog({
    required this.room,
    required this.onExportCode,
    required this.onCreateRoom,
    required this.onJoinRoom,
    super.key,
  });

  final SecureRoomSummary room;
  final ExportSecureRoomCode onExportCode;
  final CreateSecureRoom onCreateRoom;
  final JoinSecureRoom onJoinRoom;

  @override
  State<SecureRoomDialog> createState() => _SecureRoomDialogState();
}

class _SecureRoomDialogState extends State<SecureRoomDialog> {
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _roomCodeController = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _roomNameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _copyCode() async {
    if (_working) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final code = await widget.onExportCode();
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Encrypted room code copied. Share it securely.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _createRoom() async {
    final name = _roomNameController.text.trim();
    if (name.length < 2 || name.length > 32 || _working) {
      setState(() {
        _error = 'Room name must contain 2-32 characters.';
      });
      return;
    }
    await _runAndClose(() => widget.onCreateRoom(name));
  }

  Future<void> _joinRoom() async {
    final code = _roomCodeController.text.trim();
    if (code.isEmpty || _working) {
      setState(() => _error = 'Paste a MeshTalk encrypted room code.');
      return;
    }
    await _runAndClose(() => widget.onJoinRoom(code));
  }

  Future<void> _runAndClose(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('secure-room-dialog'),
      title: const Text('End-to-end encrypted room'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.room.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(
              'Key fingerprint: ${widget.room.fingerprint}',
              key: const ValueKey<String>('secure-room-fingerprint'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Messages are authenticated and encrypted before they enter BLE or local-network transports. Anyone with the room code can read and send room messages.',
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const ValueKey<String>('copy-room-code-button'),
              onPressed: _working ? null : _copyCode,
              icon: const Icon(Icons.copy),
              label: const Text('Copy room code'),
            ),
            const Divider(height: 28),
            Text(
              'Join another room',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey<String>('room-code-input'),
              controller: _roomCodeController,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Room code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey<String>('join-room-button'),
                onPressed: _working ? null : _joinRoom,
                child: const Text('Join room'),
              ),
            ),
            const Divider(height: 28),
            Text(
              'Create a new room',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey<String>('room-name-input'),
              controller: _roomNameController,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'Room name',
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey<String>('create-room-button'),
                onPressed: _working ? null : _createRoom,
                child: const Text('Create room'),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey<String>('secure-room-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
