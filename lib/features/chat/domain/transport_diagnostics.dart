import 'package:meshtalk_app/core/ble/ble_mesh_radio.dart';
import 'package:meshtalk_app/core/transport/chat_transport.dart';

class TransportDiagnosticsSnapshot {
  const TransportDiagnosticsSnapshot({
    required this.bluetoothAvailability,
    required this.refreshedAtUtc,
    this.activeTransportId,
    this.activeTransportKind,
    this.activeTransportMaxPayloadBytes,
    this.lastError,
  });

  factory TransportDiagnosticsSnapshot.initial(
    BleRadioAvailability bluetoothAvailability,
  ) {
    return TransportDiagnosticsSnapshot(
      bluetoothAvailability: bluetoothAvailability,
      refreshedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final BleRadioAvailability bluetoothAvailability;
  final DateTime refreshedAtUtc;
  final String? activeTransportId;
  final TransportKind? activeTransportKind;
  final int? activeTransportMaxPayloadBytes;
  final String? lastError;

  TransportDiagnosticsSnapshot copyWith({
    BleRadioAvailability? bluetoothAvailability,
    DateTime? refreshedAtUtc,
    String? activeTransportId,
    TransportKind? activeTransportKind,
    int? activeTransportMaxPayloadBytes,
    String? lastError,
    bool clearActiveTransport = false,
    bool clearLastError = false,
  }) {
    return TransportDiagnosticsSnapshot(
      bluetoothAvailability:
          bluetoothAvailability ?? this.bluetoothAvailability,
      refreshedAtUtc: refreshedAtUtc ?? this.refreshedAtUtc,
      activeTransportId:
          clearActiveTransport ? null : activeTransportId ?? this.activeTransportId,
      activeTransportKind: clearActiveTransport
          ? null
          : activeTransportKind ?? this.activeTransportKind,
      activeTransportMaxPayloadBytes: clearActiveTransport
          ? null
          : activeTransportMaxPayloadBytes ?? this.activeTransportMaxPayloadBytes,
      lastError: clearLastError ? null : lastError ?? this.lastError,
    );
  }
}
