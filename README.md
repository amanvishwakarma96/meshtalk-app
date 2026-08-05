# MeshTalk

MeshTalk is an offline-first mobile chat application for nearby users. Its primary transport is Bluetooth Low Energy (BLE) mesh, with platform local-network fallbacks and an optional future internet relay selected through a shared transport abstraction.

## Status

Phase 1 is under active development. The app creates a persistent local identity, starts the dual-role BLE transport, stores local history in SQLite, restores unsent messages after process restart, and delivers or relays envelopes through the mesh protocol. Android uses Nearby Connections when BLE is unavailable. iOS now uses a native Multipeer Connectivity fallback. Both local-network paths require user-confirmed comparison codes before a peer is published or application bytes are delivered. Physical multi-device validation is still required before release.

## Transport priority

1. BLE mesh
2. Android Nearby Connections on Android
3. Apple Multipeer Connectivity on iOS
4. Clearly labelled optional internet relay in a future milestone
5. Actionable no-transport state

`TransportManager` chooses and hot-swaps `ChatTransport` implementations without changing message identity, storage, relay TTL, or deduplication semantics. A higher-priority transport must activate successfully before a working fallback is disconnected. Idempotent activation is re-invoked during refresh so a native transport can recover after a runtime failure.

## Security notice

MeshTalk is **not message-level end-to-end encrypted yet**. BLE pairing or bonding may protect an individual radio link, Android Nearby protects its platform connection, and the iOS Multipeer session is configured with required link encryption. Relayed application payloads can still be readable by intermediate application peers.

Android Nearby and iOS Multipeer display a comparison code and continue only after users confirm that the same code appears on both phones. This binds the approval to the same connection attempt, but it does not make a display name a verified real-world identity. Do not use the current build for sensitive communications.

## Architecture

```text
lib/
  core/
    ble/                 # dual-role radio, frame codec, relay and reassembly
    profile/             # persistent local identity and editable name
    permissions/         # centralized runtime permission policy
    storage/             # SQLite message history and durable outbound queue
    transport/           # BLE, Android Nearby, iOS Multipeer and selection
  features/
    chat/
      data/              # multi-transport ChatSession orchestration
      domain/            # immutable UI/session and diagnostics models
      presentation/      # Riverpod page, verification UI and diagnostics
  app.dart
  app_providers.dart
  main.dart

packages/
  meshtalk_multipeer/    # private Flutter plugin and native Swift bridge
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
- publishes the platform authentication code to the UI instead of auto-accepting the connection;
- activates the byte-payload callback only after the user confirms that the codes match;
- rejects empty-token, malformed, stale, duplicate, and user-declined connection requests;
- broadcasts an envelope to every connected verified fallback peer;
- treats delivery as successful when at least one connected endpoint accepts the bytes;
- removes failed endpoints without discarding successful deliveries;
- limits encoded byte payloads to a conservative 32 KiB.

This adapter is Android-only and depends on Google Play services Nearby.

### iOS Multipeer fallback

`IosMultipeerTransport` uses `IosMultipeerGateway`. Its production implementation wraps the private `meshtalk_multipeer` Flutter plugin, which bridges to Apple's Multipeer Connectivity framework.

The iOS path:

- advertises and browses the `meshtalk-chat` service concurrently;
- includes the stable local device ID, sanitized display name, and an ephemeral nonce in discovery metadata;
- uses lexical device-ID ordering to avoid duplicate cross-invitations;
- derives a six-digit comparison code from both devices' IDs and ephemeral nonces;
- delays the outgoing invitation until the initiating user approves the code;
- delays incoming session acceptance until the receiving user approves the same code;
- configures `MCSession` with required link encryption;
- exposes peers and reliable byte payloads only after local verification completes;
- expires stale verification and connection attempts;
- shares the same 32 KiB conservative encoded-payload limit as Android Nearby;
- reports native browsing, advertising, timeout, and delivery failures through transport diagnostics.

The iOS runner is generated in CI and configured with `NSLocalNetworkUsageDescription`, the `_meshtalk-chat._tcp` Bonjour service, Bluetooth usage descriptions, and an iOS 13 deployment target.

### Shared session and storage

`ChatSession` subscribes to peer, verification, runtime-error, and incoming-message streams from every registered transport. Whichever transport is active supplies the visible peer list, while all received envelopes pass through the same relay, TTL, deduplication, SQLite, and delivery-status pipeline.

Transport refreshes are serialized so overlapping radio changes, user retries, native errors, and foreground-resume callbacks cannot start competing transport switches. When the app returns to the foreground, the session rechecks transport availability while preserving normal BLE-first priority.

`SqliteMessageStore` persists the encoded transport envelope together with room, sender label, direction, and delivery state. Message ID is the primary key, so retries and duplicate inbound events remain idempotent.

## Transport diagnostics

The diagnostics dialog shows:

- current session state;
- active transport and transport ID;
- Bluetooth radio availability;
- connected peer count;
- pending code-verification count;
- durable queued-message count;
- active transport payload limit;
- last transport refresh time;
- most recent activation, delivery, or native runtime error.

The active local fallback is labelled as Android Nearby Connections or iOS Multipeer Connectivity from its transport ID. The refresh action reruns transport selection and permission recovery. Diagnostics are local to the device and are not uploaded.

## Local profile

On first launch, MeshTalk generates and persists:

- a UUID device ID;
- a short display name derived from that ID.

The user can edit the display name from the profile dialog. Saving a new name stops the previous session before recreating BLE and platform fallback advertising. Profile values remain local in `shared_preferences`; no account, phone number, contacts access, or cloud profile is required.

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
3. Generate and configure native project folders when they are not present:

   ```bash
   flutter create --platforms=android,ios .
   bash tool/configure_android_project.sh
   bash tool/configure_ios_project.sh
   ```

   The iOS configuration script must run on macOS because it verifies the generated property list with `PlistBuddy`.

4. Install dependencies and run checks:

   ```bash
   flutter pub get
   dart format lib packages test integration_test
   flutter analyze --fatal-infos
   flutter test
   ```

5. Run on physical devices for transport validation. Simulators prove Dart/native compilation, but they do not replace two-phone BLE, Nearby, Multipeer, permission, and lifecycle testing.

## Runtime states

The chat screen distinguishes:

- Bluetooth permission denied — opens app settings;
- platform local-network permission denied or unavailable — exposes recovery and diagnostics;
- Bluetooth off with a platform fallback available — starts local discovery;
- Bluetooth off with no fallback — shows an actionable unavailable state;
- required BLE roles unsupported — explains the limitation when no fallback activates;
- scanning — messages remain queueable while the selected transport searches;
- waiting for peer verification — shows the peer name and comparison code with approve/reject actions;
- connected over BLE — shows BLE peer count;
- connected over verified Android Nearby or verified iOS Multipeer — shown only after code confirmation;
- initialization or transport error — offers retry and records the error in diagnostics.

## Android configuration

`tool/configure_android_project.sh`:

- sets `minSdk` to API 24, as required by the BLE adapter;
- declares Wi-Fi state permissions required by Nearby Connections;
- declares modern Bluetooth scan, connect, and advertise permissions;
- declares Nearby Wi-Fi and local-network permissions for newer Android versions;
- bounds legacy Bluetooth and location declarations to older Android versions;
- does not request file storage, contacts, SMS, camera, background location, or always-on location.

Only byte payloads are used by the fallback, so file-storage permission is unnecessary.

## iOS configuration

`tool/configure_ios_project.sh`:

- sets the iOS deployment target to 13.0;
- adds the Local Network usage description;
- registers `_meshtalk-chat._tcp` under `NSBonjourServices`;
- adds Bluetooth central/peripheral usage descriptions used by the BLE path;
- is idempotent and safe to rerun after regenerating the iOS project.

The current milestone does not request background Multipeer restoration or claim background discovery support.

## CI artifacts

### Android APK

The `Android APK` workflow generates the Android scaffold when needed, applies Android transport configuration, builds a release APK, creates a SHA-256 checksum, and uploads the artifact for 14 days. The APK uses Flutter development signing and is for internal testing only.

### iOS simulator

The `iOS Simulator` workflow runs on macOS, generates the iOS runner when needed, applies the local-network configuration, resolves CocoaPods, compiles the Swift plugin, builds an unsigned simulator app, creates a SHA-256 checksum, and uploads it for 14 days.

The simulator artifact cannot be installed on a physical iPhone. A signed development or distribution build still requires an Apple Developer team, provisioning profile, signing certificate, and real-device verification.

## Dependency notes

- `bluetooth_low_energy` 6.2.1 provides BLE central and peripheral roles on Android and iOS.
- `nearby_connections` 4.3.0 provides Android Nearby Connections only.
- `meshtalk_multipeer` is a private path plugin that wraps Apple's Multipeer Connectivity framework.
- `device_info_plus` is pinned to 11.4.0 to retain the project’s Dart 3.6 baseline while selecting version-specific Android permissions.
- `shared_preferences` 2.5.3 stores non-sensitive profile preferences.
- `sqflite` 2.4.1 stores message history while retaining Dart 3.6 compatibility.
- `sqflite_common_ffi` is test-only and exercises the real SQLite schema in memory.

## Known limitations

- Message-level end-to-end encryption is not implemented.
- Matching comparison codes verify a platform connection attempt, not either peer's real-world identity.
- Platform local-network fallbacks activate when BLE is unavailable; they do not currently start merely because BLE has zero connected peers.
- Android Nearby depends on Google Play services and requires cross-vendor physical testing.
- iOS Multipeer requires two physical iPhones for Local Network permission, discovery, invitation, and lifecycle validation.
- BLE and local-network transports are foreground-first. The app refreshes transports after foreground resume, but full background restoration requires platform-specific lifecycle work.
- Symmetric BLE discovery can create more than one logical path. Message IDs and deduplication remain authoritative.
- The compact BLE frame format supports at most 255 chunks per message.
- Internet relay is not implemented.
- History has no retention, export, or delete controls.
- Real-device verification on at least two phones per platform is required before nearby transports are considered release-ready.

## Development process

- Never push feature work directly to `main`.
- Use Conventional Commits.
- Every user-facing change updates `CHANGELOG.md`.
- Every core/domain feature requires tests.
- Storage schema changes require migration tests.
- Real-device transport changes require the checklist in `docs/manual-test-checklist.md`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch, PR, testing, and release rules. The focused iOS milestone checklist is in [docs/pr8-validation-plan.md](docs/pr8-validation-plan.md).
