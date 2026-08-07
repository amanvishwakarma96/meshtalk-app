import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meshtalk_app/app_providers.dart';
import 'package:meshtalk_app/core/security/room_membership.dart';
import 'package:meshtalk_app/core/security/room_membership_manager.dart';
import 'package:meshtalk_app/core/security/secure_room.dart';

class RoomMembershipDialog extends ConsumerStatefulWidget {
  const RoomMembershipDialog({super.key});

  @override
  ConsumerState<RoomMembershipDialog> createState() =>
      _RoomMembershipDialogState();
}

class _RoomMembershipDialogState extends ConsumerState<RoomMembershipDialog> {
  final TextEditingController _joinRequestController = TextEditingController();
  final TextEditingController _inviteController = TextEditingController();

  SecureRoom? _room;
  List<RoomMemberSummary> _members = const <RoomMemberSummary>[];
  Map<String, String> _rotationUpdates = const <String, String>{};
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_reload);
  }

  @override
  void dispose() {
    _joinRequestController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<RoomMembershipManager> _manager() {
    return ref.read(roomMembershipManagerProvider.future);
  }

  Future<void> _reload() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final room = await ref.read(secureRoomStoreProvider).loadActive();
      if (room == null) {
        throw StateError('No active encrypted room is configured.');
      }
      final manager = await _manager();
      List<RoomMemberSummary> members;
      try {
        await manager.ensureLocalMembership(room);
        members = await manager.listCurrentMembers(room);
      } on StateError {
        members = await manager.listCurrentMembers(room);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _room = room;
        _members = members;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _copyText(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied.')),
    );
  }

  Future<void> _copyJoinRequest() async {
    await _run(() async {
      final code = await (await _manager()).createJoinRequestCode();
      await _copyText(code, 'Signed join request');
    });
  }

  Future<void> _issueInvite() async {
    final request = _joinRequestController.text.trim();
    final room = _room;
    if (room == null || request.isEmpty) {
      return;
    }
    await _run(() async {
      final code = await (await _manager()).issueInvite(
        room: room,
        joinRequestCode: request,
      );
      _joinRequestController.clear();
      await _copyText(code, 'Member invite');
      await _reload();
    });
  }

  Future<void> _importInvite() async {
    final code = _inviteController.text.trim();
    if (code.isEmpty) {
      return;
    }
    await _run(() async {
      await (await _manager()).importInvite(code);
      _inviteController.clear();
      ref.invalidate(activeSecureRoomProvider);
      ref.invalidate(chatSessionProvider);
      await _reload();
    });
  }

  Future<void> _removeMember(RoomMemberSummary member) async {
    final room = _room;
    if (room == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove ${member.deviceId} and rotate the room key? The removed device will not receive the next epoch key.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove & rotate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _run(() async {
      final result = await (await _manager()).removeMember(
        room: room,
        memberDeviceId: member.deviceId,
      );
      ref.invalidate(activeSecureRoomProvider);
      ref.invalidate(chatSessionProvider);
      if (!mounted) {
        return;
      }
      setState(() {
        _room = result.room;
        _rotationUpdates = result.memberUpdateCodes;
      });
      await _reload();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  bool get _isOwner => _members.any(
        (member) => member.isLocal && member.role == RoomMemberRole.owner,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Room members'),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(child: _content(context)),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final room = _room;
    if (room == null) {
      return Text(_error ?? 'No encrypted room is available.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${room.name} · epoch ${room.epoch} · ${_members.length} member${_members.length == 1 ? '' : 's'}',
          key: const ValueKey<String>('room-members-summary'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _isOwner
              ? 'You are the room owner. New members must provide a signed join request before you can issue their encrypted invite.'
              : 'To join or update this room, exchange owner-signed membership codes through a trusted channel.',
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey<String>('room-members-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          key: const ValueKey<String>('copy-join-request-button'),
          onPressed: _working ? null : _copyJoinRequest,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Copy my signed join request'),
        ),
        if (_isOwner) ...<Widget>[
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey<String>('member-join-request-input'),
            controller: _joinRequestController,
            enabled: !_working,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Member join request (MTJ1)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey<String>('issue-member-invite-button'),
            onPressed: _working ? null : _issueInvite,
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Create & copy member invite'),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey<String>('membership-invite-input'),
          controller: _inviteController,
          enabled: !_working,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Owner-signed invite / epoch update (MTI1)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey<String>('apply-membership-invite-button'),
          onPressed: _working ? null : _importInvite,
          icon: const Icon(Icons.download_for_offline_outlined),
          label: const Text('Verify & apply membership update'),
        ),
        const SizedBox(height: 20),
        Text('Current epoch members', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final member in _members) _memberTile(member),
        if (_rotationUpdates.isNotEmpty) ...<Widget>[
          const Divider(height: 28),
          Text(
            'Next-epoch update codes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Send each code only to its named remaining member. The removed device has no code for this epoch.',
          ),
          const SizedBox(height: 8),
          for (final entry in _rotationUpdates.entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(entry.key),
              subtitle: Text('Epoch ${room.epoch} key update'),
              trailing: IconButton(
                key: ValueKey<String>('copy-epoch-update-${entry.key}'),
                onPressed: _working
                    ? null
                    : () => _copyText(entry.value, 'Epoch update'),
                icon: const Icon(Icons.copy),
                tooltip: 'Copy update',
              ),
            ),
        ],
      ],
    );
  }

  Widget _memberTile(RoomMemberSummary member) {
    final isOwner = member.role == RoomMemberRole.owner;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(isOwner ? Icons.admin_panel_settings : Icons.person_outline),
      title: Text(member.isLocal ? '${member.deviceId} (this device)' : member.deviceId),
      subtitle: Text(
        '${isOwner ? 'Owner' : 'Member'} · epoch ${member.epoch} · signing ${member.signingKeyId}',
      ),
      trailing: _isOwner && !member.isLocal
          ? IconButton(
              key: ValueKey<String>('remove-room-member-${member.deviceId}'),
              onPressed: _working ? null : () => _removeMember(member),
              icon: const Icon(Icons.person_remove_outlined),
              tooltip: 'Remove and rotate key',
            )
          : null,
    );
  }
}
