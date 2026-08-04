# MeshTalk

MeshTalk is an offline-first mobile chat application for nearby users. Its primary transport is Bluetooth Low Energy (BLE) mesh, with local Wi-Fi and optional internet relay fallbacks selected through a transport abstraction.

## Status

Phase 1 is under active development. The app now creates a persistent local identity, starts the dual-role BLE transport, shows live permission/radio/peer state, stores local history in SQLite, restores unsent messages after process restart, and delivers or relays received envelopes through the mesh protocol. Local Wi-Fi and internet fallback transports are still pending.

## Transport priority

1. BLE mesh
2. Local Wi-Fi / Nearby Connections / Multipeer Connectivity
3. Clearly labelled internet relay
4. Actionable no-transport state

The chat feature does not depend directly on a BLE plugin. `TransportManager` chooses and hot-swaps `ChatTransport` implementations without changing message identity or relay semantics.

## Security notice

MeshTalk is **not end-to-end encrypted yet**. BLE pairing or bonding may protect an individual radio link, but relayed message payloads remain readable at the application layer by intermediate peers. Do not use the current build for sensitive communications. This warning remains visible in the chat UI until message-level encryption ships.

## Architecture

```text
lib/
  core/
    ble/                 # dual-role radio, frame codec, relay and reassembly
    profile/             # persistent local identity and editable name
    permissions/         # centralized runtime permission policy
    storage/             # SQLite message history and durable outbound queue
    transport/           # ChatTransport, BLE transport and TransportManager
  features/
    chat/
      data/              # runtime ChatSession orchestration
      domain/            # immutable UI/session models
      presentation/      # Riverpod page and testable widgets
    diagnostics/
    ble_console/
  app.dart
  app_providers.dart
  main.dart
```

`BluetoothLowEnergyMeshRadio` simultaneously:

- advertises the MeshTalk GATT service as a peripheral;
- scans for the same service as a central;
- connects to discovered peers and subscribes to notifications;
- accepts characteristic writes from remote centrals;
- broadcasts frames through writes and notifications;
- reports connected peers and negotiated frame limits.

`BleTransport` remains plugin-independent. It converts message envelopes into compact BLE frames, sends them through `BleMeshRadio`, and reassembles inbound frames.

`ChatSession` owns runtime orchestration. It starts BLE authorization, maps permission/off/unsupported states into actionable UI, loads local history, restores queued outbound envelopes, marks local IDs as seen, applies relay TTL/dedup decisions, and retries pending messages when a peer appears.

`SqliteMessageStore` persists the encoded transport envelope together with room, sender label, direction, and delivery state. Writes use message ID as the primary key so retries and duplicate inbound events remain idempotent.

## Local profile

On first launch, MeshTalk generates and persists:

- a UUID device ID;
- a short display name derived from that ID.

The user can edit the display name from the profile dialog. Saving a new name recreates the BLE session so the updated identity is advertised immediately. Profile values are stored locally with `shared_preferences`; no account, server, phone number, contacts access, or cloud profile is required.

## Durable history and queue recovery

- Incoming, queued, and sent messages are stored in SQLite.
- Room history is loaded in timestamp order when the app starts.
- Outgoing messages are written as queued before the transport attempts delivery.
- Only successful transport sends change an outgoing message to sent.
- Queued envelopes are restored after process restart and retried when a peer connects.
- Message IDs deduplicate restored queue entries and radio echoes.

The database currently uses schema version 1. Future schema changes must add explicit migrations and preserve existing history.

## Getting started

1. Install a current stable Flutter SDK with Dart 3.6 or newer.
2. Clone the repository.
3. Generate native project folders if they are not present:

   ```bash
   flutter create --platforms=android,ios .
   bash tool/configure_android_project.sh
   ```

4. For iOS, add these Bluetooth usage descriptions to `ios/Runner/Info.plist` before running on a device:

   ```xml
   <key>NSBluetoothAlwaysUsageDescription</key>
   <string>MeshTalk uses Bluetooth to discover and communicate with nearby peers.</string>
   <key>NSBluetoothPeripheralUsageDescription</key>
   <string>MeshTalk advertises a local Bluetooth service for offline nearby chat.</string>
   ```

5. Install dependencies and run checks:

   ```bash
   flutter pub get
   flutter analyze
   flutter test
   ```

6. Run the app on physical Android and iOS devices. BLE central/peripheral behavior cannot be validated reliably on simulators.

## Runtime states

The chat screen distinguishes these states instead of showing a generic failure:

- Bluetooth permission denied — opens app settings;
- Bluetooth off — asks the user to enable Bluetooth and retry;
- required BLE roles unsupported — explains the hardware limitation;
- scanning — messages can be queued while MeshTalk searches for peers;
- connected — shows the live nearby-peer count;
- initialization or transport error — offers a retry action.

## Android BLE configuration

`tool/configure_android_project.sh` makes the generated Android project compatible with the BLE adapter:

- sets `minSdk` to API 24, as required by `bluetooth_low_energy`;
- declares `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, and `BLUETOOTH_ADVERTISE`;
- keeps legacy Bluetooth and foreground location permissions limited to Android 11 and older;
- does not request background or always-on location.

## Android APK artifacts

The `Android APK` GitHub Actions workflow runs for Android-relevant pull requests, pushes to `main`, and manual workflow dispatches. It generates the Android scaffold when needed, applies BLE configuration, builds a release APK, creates a SHA-256 checksum, and uploads the artifact for 14 days.

The generated APK uses the default Flutter development signing configuration and is intended for internal installation and testing only. A Play Store build requires maintainer-approved release signing secrets and an Android App Bundle workflow.

## Dependency notes

- `bluetooth_low_energy` 6.2.1 is used because MeshTalk requires both BLE central and peripheral roles on Android and iOS.
- `shared_preferences` 2.5.3 stores non-sensitive profile preferences while retaining Dart 3.6 compatibility.
- `sqflite` 2.4.1 stores message history on Android and iOS while retaining Dart 3.6 compatibility. Newer releases require a newer Dart baseline.
- `sqflite_common_ffi` is a test-only dependency used to exercise the real SQLite schema in memory.
- `nearby_connections` 4.3.0 exposes Android Nearby Connections, not iOS Multipeer Connectivity. A separate iOS adapter is required for equivalent fallback behavior.
- Permissions remain limited to Bluetooth scan/connect/advertise, foreground location where required for legacy discovery, local-network access, and notifications.

## Known limitations

- Message-level end-to-end encryption is not implemented.
- The BLE adapter is foreground-first. Background advertising, restoration, and long-lived background connections require platform-specific lifecycle work and real-device validation.
- Symmetric phone-to-phone discovery may create more than one logical path between two devices. Message IDs and deduplication remain authoritative.
- The compact BLE frame format supports at most 255 chunks per message.
- Local Wi-Fi and internet fallback transports are not implemented yet.
- History has no retention, export, or delete controls yet.
- Real-device verification on at least two phones is required before this transport is considered release-ready.

## Development process

- Never push feature work directly to `main`.
- Use Conventional Commits.
- Every user-facing change updates `CHANGELOG.md`.
- Every core/domain feature requires tests.
- Storage schema changes require migration tests.
- Real-device changes to `core/ble/` require the manual checklist in `docs/manual-test-checklist.md`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch, PR, testing, and release rules.
