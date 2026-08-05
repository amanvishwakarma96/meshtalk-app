import 'package:flutter/material.dart';
import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';
import 'package:meshtalk_app/features/chat/domain/chat_session_state.dart';

typedef RefreshDiagnostics = Future<void> Function();

class TransportDiagnosticsDialog extends StatefulWidget {
  const TransportDiagnosticsDialog({
    required this.state,
    required this.onRefresh,
    super.key,
  });

  final ChatSessionState state;
  final RefreshDiagnostics onRefresh;

  @override
  State<TransportDiagnosticsDialog> createState() =>
      _TransportDiagnosticsDialogState();
}

class _TransportDiagnosticsDialogState
    extends State<TransportDiagnosticsDialog> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = widget.state.diagnostics;
    return AlertDialog(
      key: const ValueKey<String>('transport-diagnostics-dialog'),
      title: const Text('Transport diagnostics'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _DiagnosticRow(
              label: 'Session',
              value: _sessionLabel(widget.state.status),
            ),
            const _DiagnosticRow(
              label: 'Encryption',
              value: 'XChaCha20-Poly1305 group E2EE',
            ),
            _DiagnosticRow(
              label: 'Secure room',
              value: widget.state.secureRoom.name,
            ),
            _DiagnosticRow(
              label: 'Key fingerprint',
              value: widget.state.secureRoom.fingerprint,
            ),
            _DiagnosticRow(
              label: 'Active transport',
              value: _transportLabel(
                diagnostics?.activeTransportKind ??
                    widget.state.activeTransportKind,
                diagnostics?.activeTransportId,
              ),
            ),
            _DiagnosticRow(
              label: 'Transport ID',
              value: diagnostics?.activeTransportId ?? 'None',
            ),
            _DiagnosticRow(
              label: 'Bluetooth',
              value: _bluetoothLabel(diagnostics?.bluetoothAvailability),
            ),
            _DiagnosticRow(
              label: 'Connected peers',
              value: '${widget.state.peers.length}',
            ),
            _DiagnosticRow(
              label: 'Waiting verification',
              value: '${widget.state.verificationRequests.length}',
            ),
            _DiagnosticRow(
              label: 'Queued messages',
              value: '${widget.state.pendingCount}',
            ),
            _DiagnosticRow(
              label: 'Payload limit',
              value: _payloadLabel(
                diagnostics?.activeTransportMaxPayloadBytes,
              ),
            ),
            _DiagnosticRow(
              label: 'Last refresh',
              value: _timeLabel(diagnostics?.refreshedAtUtc),
            ),
            const SizedBox(height: 8),
            Text(
              'Last transport or encryption error',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            SelectableText(
              diagnostics?.lastError ?? 'None',
              key: const ValueKey<String>('diagnostics-last-error'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _refreshing ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey<String>('diagnostics-refresh-button'),
          onPressed: _refreshing ? null : _refresh,
          icon: _refreshing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  String _sessionLabel(ChatConnectionStatus status) {
    return switch (status) {
      ChatConnectionStatus.initializing => 'Initializing',
      ChatConnectionStatus.permissionDenied => 'Bluetooth permission denied',
      ChatConnectionStatus.localNetworkPermissionDenied =>
        'Local-network permission denied',
      ChatConnectionStatus.bluetoothOff => 'Bluetooth off',
      ChatConnectionStatus.unsupported => 'Unsupported',
      ChatConnectionStatus.scanning => 'Searching',
      ChatConnectionStatus.connected => 'Connected',
      ChatConnectionStatus.error => 'Error',
    };
  }

  String _transportLabel(TransportKind? kind, String? transportId) {
    return switch (kind) {
      TransportKind.bleMesh => 'Bluetooth LE mesh',
      TransportKind.localWifi => switch (transportId) {
          'android-nearby' => 'Android Nearby Connections',
          'ios-multipeer' => 'iOS Multipeer Connectivity',
          _ => 'Local-network fallback',
        },
      TransportKind.internetRelay => 'Internet relay',
      null => 'None',
    };
  }

  String _bluetoothLabel(BleRadioAvailability? availability) {
    return switch (availability) {
      BleRadioAvailability.ready => 'Ready',
      BleRadioAvailability.poweredOff => 'Powered off',
      BleRadioAvailability.unauthorized => 'Unauthorized',
      BleRadioAvailability.unsupported => 'Unsupported',
      null => 'Unknown',
    };
  }

  String _payloadLabel(int? bytes) {
    if (bytes == null) {
      return 'Dynamic / unknown';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    return '$bytes bytes';
  }

  String _timeLabel(DateTime? timestampUtc) {
    if (timestampUtc == null || timestampUtc.millisecondsSinceEpoch == 0) {
      return 'Not refreshed yet';
    }
    final local = timestampUtc.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
