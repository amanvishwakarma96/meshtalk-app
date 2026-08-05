# MeshTalk

MeshTalk is an offline-first mobile chat application for nearby users. Its primary transport is Bluetooth Low Energy (BLE) mesh, with local transports and an optional internet relay selected through a transport abstraction.

## Status

Phase 1 is under active development. The app creates a persistent local identity, starts the dual-role BLE transport, stores local history in SQLite, restores unsent messages after process restart, and delivers or relays envelopes through the mesh protocol. Android now has a Nearby Connections fallback when BLE is unavailable. Equivalent iOS fallback behavior and the optional internet relay remain pending.

## Transport priority

1. BLE mesh
2. Android Nearby Connections fallback
3. Future iOS Network or Multipeer adapter
4. Clearly labelled optional internet relay
5. Actionable no-transport state

`TransportManager` chooses and hot-swaps `ChatTransport` implementations without changing message identity, storage, relay TTL, or deduplication semantics. A higher-priority transport must activate successfully before a working fallback is disconnected.

## Security notice

MeshTalk is **not end-to-end encrypted yet**. BLE pairing or bonding may protect an individual radio link, but relayed application payloads remain readable by intermediate peers. Android Nearby connections are currently accepted only when the endpoint advertises a valid MeshTalk identity, but that identity and the platform authentication token are not yet confirmed by the user. The fallback is therefore explicitly labelled unverified. Do not use the current build for sensitive communications.

## Architecture

```text
lib/
  core/
    ble/                 # dual-role radio, frame codec, relay and reassembly
    profile/             # persistent local identity and editable name
    permissions/         # centralized runtime permission policy
    storage/             # SQLite message history and durable outbound queue
    transport/           # BLE, Android Nearby, contracts and selection manager
  features/
    chat/
      data/              # multi-transport ChatSession orchestration
      domain/            # immutable UI/session models
      presentation/      # Riverpod page and testable widgets
    diagnostics/
    ble_console/
  app.dart
  app_providers.dart
  main.dart
```

### BLE path

`BluetoothLowEnergyMeshRadio` simultaneously advertises the MeshTalk GATT service, scans for the same service, connects as a central, accepts writes as a peripheral, sends notifications, and reports negotiated frame limits. `BleTransport` converts message envelopes into compact BLE frames and reassembles inbound chunks.

### Android Nearby fallback

`AndroidNearbyTransport` uses the plugin-neutral `NearbyConnectionsGateway` contract. Its production gateway wraps Android Nearby Connections with the P2P cluster strategy.

The transport:

- starts advertising and discovery only after version-appropriate runtime permission checks;
- advertises a stable MeshTalk endpoint identity containing the local device ID and sanitized display name;
- ignores malformed and self-identifying endpoints;
- uses lexical device-ID ordering so only one side initiates a discovered connection;
- accepts byte payloads and decodes them through the existing `MessageCodec`;
- broadcasts an envelope to every connected fallback peer;
- treats delivery as successful when at least one connected endpoint accepts the bytes;
- removes failed endpoints without discarding successful deliveries;
- limits encoded byte payloads to a conservative 32 KiB.

This adapter is Android-only. It is not presented as iOS Multipeer Connectivity support.

### Shared session and storage

`ChatSession` subscribes to peer and incoming-message streams from every registered transport. Whichever transport is active supplies the visible peer list, while all received envelopes pass through the same relay, TTL, deduplication, SQLite, and delivery-status pipeline.

`SqliteMessageStore` persists the encoded transport envelope together with room, sender label, direction, and delivery state. Message ID is the primary key, so retries and duplicate inbound events remain idempotent.

## Local profile

On first launch, MeshTalk generates and persists:

- a UUID device ID;
- a short display name derived from that ID.

The user can edit the display name from the profile dialog. Saving a new name stops the previous session before recreating BLE and Android Nearby advertising. Profile values remain local in `shared_preferences`; no account, phone number, contacts access, or cloud profile is required.

## Durable history and queue recovery

- Incoming, queued, and sent messages are stored in SQLite.
- Room history loads in timestamp order when the app starts.
- Outgoing messages are written as queued before transport delivery.
- Only successful transport sends change an outgoing message to sent.
- Queued envelopes survive process restart and retry when the active transport gains a peer.
- Message IDs deduplicate restored queue entries, BLE echoes, and cross-transport duplicates.

The database currently uses schema version 1. Future schema changes must add explicit migrations and preserve existing history.

## Getting started

1. Install a current stable Flutter SDK with Dart 3.6 or newer.
2. Clone the repository.
3. Generate native project folders if they are not present:

   ```bash
   flutter create --platforms=android,ios .
   bash tool/configure_android_project.sh
   ```

4. For iOS BLE, add these descriptions to `ios/Runner/Info.plist`:

   ```xml
   <key>NSBluetoothAlwaysUsageDescription</key>
   <string>MeshTalk uses Bluetooth to discover and communicate with nearby peers.</string>
   <key>NSBluetoothPeripheralUsageDescription</key>
   <string>MeshTalk advertises a local Bluetooth service for offline nearby chat.</string>
   ```

   A future iOS local-network fallback will also require local-network and Bonjour declarations. Those are intentionally not claimed or configured yet.

5. Install dependencies and run checks:

   ```bash
   flutter pub get
   flutter analyze
   flutter test
   ```

6. Run the app on physical devices. BLE central/peripheral and Android Nearby behavior cannot be validated reliably on simulators.

## Runtime states

The chat screen distinguishes:

- Bluetooth permission denied — opens app settings;
- Android Nearby/local-network permission denied — opens app settings;
- Bluetooth off with fallback available — starts Android Nearby discovery;
- Bluetooth off with no fallback — shows an actionable unavailable state;
- required BLE roles unsupported — explains the limitation when no fallback activates;
- scanning — messages remain queueable while the selected transport searches;
- connected over BLE — shows BLE peer count;
- connected over Android Nearby — labels the fallback and displays an unauthenticated-peer warning;
- initialization or transport error — offers retry.

## Android configuration

`tool/configure_android_project.sh`:

- sets `minSdk` to API 24, as required by the BLE adapter;
- declares Wi-Fi state permissions required by Nearby Connections;
- declares modern Bluetooth scan, connect, and advertise permissions;
- declares Nearby Wi-Fi and local-network permissions for newer Android versions;
- bounds legacy Bluetooth and location declarations to older Android versions;
- does not request file storage, contacts, SMS, camera, background location, or always-on location.

Only byte payloads are used by the fallback, so file-storage permission is unnecessary.

## Android APK artifacts

The `Android APK` GitHub Actions workflow runs for Android-relevant pull requests, pushes to `main`, and manual dispatches. It generates the Android scaffold when needed, applies Android transport configuration, builds a release APK, creates a SHA-256 checksum, and uploads the artifact for 14 days.

The APK uses Flutter’s development signing configuration and is for internal installation and testing only. A Play Store build requires maintainer-approved release signing secrets and an Android App Bundle workflow.

## Dependency notes

- `bluetooth_low_energy` 6.2.1 provides BLE central and peripheral roles on Android and iOS.
- `nearby_connections` 4.3.0 provides Android Nearby Connections only.
- `device_info_plus` is pinned to 11.4.0 to retain the project’s Dart 3.6 baseline while selecting version-specific Android permissions.
- `shared_preferences` 2.5.3 stores non-sensitive profile preferences.
- `sqflite` 2.4.1 stores message history while retaining Dart 3.6 compatibility.
- `sqflite_common_ffi` is test-only and exercises the real SQLite schema in memory.

## Known limitations

- Message-level end-to-end encryption is not implemented.
- Android Nearby peer identity is not cryptographically authenticated or user-confirmed yet.
- Android Nearby activates when BLE is unavailable; it does not currently start merely because BLE has zero connected peers.
- The Android fallback depends on Google Play services Nearby and requires real-device interoperability testing across Android versions and vendors.
- An equivalent iOS local-network fallback is not implemented.
- BLE and Android Nearby are foreground-first; background restoration requires platform-specific lifecycle work.
- Symmetric BLE discovery can create more than one logical path. Message IDs and deduplication remain authoritative.
- The compact BLE frame format supports at most 255 chunks per message.
- Internet relay is not implemented.
- History has no retention, export, or delete controls.
- Real-device verification on at least two phones is required before either nearby transport is considered release-ready.

## Development process

- Never push feature work directly to `main`.
- Use Conventional Commits.
- Every user-facing change updates `CHANGELOG.md`.
- Every core/domain feature requires tests.
- Storage schema changes require migration tests.
- Real-device transport changes require the checklist in `docs/manual-test-checklist.md`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch, PR, testing, and release rules.
