import 'package:flutter/material.dart';
import 'package:meshtalk_app/core/security/device_identity.dart';
import 'package:meshtalk_app/core/security/identity_trust_store.dart';

typedef TrustedIdentityAction = Future<void> Function(
  TrustedIdentitySummary identity,
);

class TrustedIdentitiesDialog extends StatefulWidget {
  const TrustedIdentitiesDialog({
    required this.localIdentity,
    required this.identities,
    required this.onVerify,
    required this.onAcceptChange,
    required this.onRejectChange,
    super.key,
  });

  final DeviceIdentitySummary localIdentity;
  final List<TrustedIdentitySummary> identities;
  final TrustedIdentityAction onVerify;
  final TrustedIdentityAction onAcceptChange;
  final TrustedIdentityAction onRejectChange;

  @override
  State<TrustedIdentitiesDialog> createState() =>
      _TrustedIdentitiesDialogState();
}

class _TrustedIdentitiesDialogState extends State<TrustedIdentitiesDialog> {
  String? _workingDeviceId;

  Future<void> _run(
    TrustedIdentitySummary identity,
    TrustedIdentityAction action,
  ) async {
    if (_workingDeviceId != null) {
      return;
    }
    setState(() => _workingDeviceId = identity.deviceId);
    try {
      await action(identity);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The selected identity state is no longer current.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _workingDeviceId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey<String>('trusted-identities-dialog'),
      title: const Text('Device identities'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'This device',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              SelectableText(
                widget.localIdentity.fingerprint,
                key: const ValueKey<String>('local-identity-fingerprint'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Compare fingerprints through a trusted channel before marking another device verified.',
              ),
              const Divider(height: 24),
              if (widget.identities.isEmpty)
                const Text(
                  'No signed peer identity has been seen in this room yet.',
                )
              else
                ...widget.identities.map(_identityCard),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _workingDeviceId == null
              ? () => Navigator.of(context).pop()
              : null,
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _identityCard(TrustedIdentitySummary identity) {
    final working = _workingDeviceId == identity.deviceId;
    final shortDeviceId = identity.deviceId.length <= 12
        ? identity.deviceId
        : '${identity.deviceId.substring(0, 12)}…';
    return Card.outlined(
      key: ValueKey<String>('trusted-identity-${identity.deviceId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  identity.trustLevel == IdentityTrustLevel.verified
                      ? Icons.verified_user
                      : Icons.person_search,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shortDeviceId,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  identity.trustLevel == IdentityTrustLevel.verified
                      ? 'Verified'
                      : 'First seen',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              identity.fingerprint,
              key: ValueKey<String>(
                'identity-fingerprint-${identity.deviceId}',
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            if (identity.hasPendingChange) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Identity changed',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Messages from the new key are blocked until you compare and approve its fingerprint.',
              ),
              const SizedBox(height: 4),
              SelectableText(
                identity.pendingFingerprint!,
                key: ValueKey<String>(
                  'pending-identity-fingerprint-${identity.deviceId}',
                ),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    key: ValueKey<String>(
                      'reject-identity-change-${identity.deviceId}',
                    ),
                    onPressed: working
                        ? null
                        : () => _run(identity, widget.onRejectChange),
                    child: const Text('Keep old key'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    key: ValueKey<String>(
                      'accept-identity-change-${identity.deviceId}',
                    ),
                    onPressed: working
                        ? null
                        : () => _run(identity, widget.onAcceptChange),
                    child: const Text('Approve new key'),
                  ),
                ],
              ),
            ] else if (identity.trustLevel == IdentityTrustLevel.seen) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  key: ValueKey<String>(
                    'verify-identity-${identity.deviceId}',
                  ),
                  onPressed:
                      working ? null : () => _run(identity, widget.onVerify),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Fingerprint matches'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
