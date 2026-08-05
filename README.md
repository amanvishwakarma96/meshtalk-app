# MeshTalk

MeshTalk is an offline-first mobile chat application for nearby users. Its primary transport is Bluetooth Low Energy (BLE) mesh, with Android Nearby Connections and Apple Multipeer Connectivity fallbacks selected through a shared transport abstraction.

## Status

Phase 1 is under active development. MeshTalk creates a persistent local identity, selects a nearby transport, stores local history in SQLite, restores unsent messages after process restart, and relays envelopes through the mesh protocol.

New messages now use shared-key group end-to-end encryption. Android and iOS native builds compile in CI, but physical multi-device encryption, transport, permission, secure-storage, and lifecycle validation is still required before release.

## Transport priority

1. BLE mesh
2. Android Nearby Connections on Android
3. Apple Multipeer Connectivity on iOS
4. Clearly labelled optional internet relay in a future milestone
5. Actionable no-transport state

`TransportManager` chooses and hot-swaps `ChatTransport` implementations without changing message identity, room identity, storage, relay TTL, or deduplication semantics. A higher-priority transport must activate successfully before a working fallback is disconnected.

## End-to-end encrypted rooms

MeshTalk creates a local encrypted room on first launch. A room contains:

- a random 256-bit symmetric key;
- a random room identifier;
- a human-readable local name;
- a short fingerprint derived from the key.

New message text is encrypted with XChaCha20-Poly1305 before it enters SQLite or any BLE, Nearby, or Multipeer transport. The authenticated payload frame contains a version, algorithm identifier, room-key identifier, 24-byte nonce, authentication tag, and ciphertext.

The following immutable envelope fields are bound to the authentication tag as associated data:

- message ID;
- sender device ID;
- room ID;
- UTC timestamp.

The relay hop limit is intentionally excluded from the authenticated data so an intermediate mesh node can decrement TTL without possessing the room key. Message IDs and the existing seen-message cache remain authoritative for replay and duplicate suppression.

### Joining a room

The room owner copies a versioned MeshTalk room code and shares it through a trusted channel. The code contains the room ID, room key, room name, and a checksum that catches accidental or malicious text modification before import.

Anyone who obtains the room code becomes a full group member: they can decrypt existing ciphertext they receive and create valid new messages. Treat the code like a password or recovery key. The short fingerprint is useful for confirming that devices imported the same key, but it is not a substitute for securely sharing the full room code.

Room keys are stored through `flutter_secure_storage`, using platform secure-storage facilities. Corrupt secure-room storage fails initialization instead of silently replacing keys.

### Security boundary

This milestone provides authenticated shared-key group encryption. It protects message content from transport providers and relay-only peers that do not possess the room key.

It does **not** yet provide:

- Signal-style per-member identity keys;
- forward secrecy or post-compromise security;
- automatic key rotation;
- member removal or revocation;
- proof of a person's real-world identity;
- protection after the room code or device key storage is compromised.

Transport and routing metadata remains visible to nearby participants and relays, including message IDs, sender device IDs, room IDs, timestamps, hop limits, payload lengths, and transport-level peer information. Message text remains ciphertext.

## Legacy history and migration

Messages created before encrypted rooms remain readable from local SQLite and are labelled **legacy unencrypted history**. They are not retroactively encrypted in place.

A pending legacy plaintext outbound message is converted to the active room's authenticated ciphertext before it is restored into the transport queue. Wrong-key, malformed, or tampered network payloads are never displayed or persisted as received messages.

Loss of the room key makes encrypted history unreadable. Keep the room code in a secure location when recovery is required. Application reinstall and secure-storage restoration behavior varies by platform and device policy, so the room code remains the portable recovery mechanism.

## Architecture

```text
lib/
  core/
    ble/                 # dual-role radio, frame codec, relay and reassembly
    profile/             # persistent local identity and editable name
    permissions/         # centralized runtime permission policy
    security/            # encrypted rooms, room codes and AEAD protection
    storage/             # SQLite ciphertext history and durable outbound queue
    transport/           # BLE, Android Nearby, iOS Multipeer and selection
  features/
    chat/
      data/              # encrypted multi-transport ChatSession orchestration
      domain/            # immutable UI/session and diagnostics models
      presentation/      # room, verification and diagnostics UI
  app.dart
  app_providers.dart
  main.dart

packages/
  meshtalk_multipeer/    # private Flutter plugin and native Swift bridge
```

### Encryption path

`MessageProtector` uses XChaCha20-Poly1305 authenticated encryption. `SecureRoomCodeCodec` creates and validates offline room codes, while `SecureRoomStore` maintains a versioned secure keyring.

`ChatSession`:

- encrypts outgoing text before persistence and transport delivery;
- stores new outgoing and incoming payloads as ciphertext;
- decrypts authenticated active-room payloads for display;
- rejects tampered, malformed, wrong-key, and unauthenticated network messages;
- labels legacy local plaintext history;
- migrates queued legacy plaintext before transmission;
- relays ciphertext for other rooms without decrypting or displaying it;
- records encryption failures in local diagnostics.

### BLE path

`BluetoothLowEnergyMeshRadio` simultaneously advertises the MeshTalk GATT service, scans for the same service, connects as a central, accepts writes as a peripheral, sends notifications, and reports negotiated frame limits. `BleTransport` converts encrypted message envelopes into compact BLE frames and reassembles inbound chunks.

### Android Nearby fallback

`AndroidNearbyTransport` wraps Android Nearby Connections with the P2P cluster strategy. It starts only after version-appropriate permissions, rejects malformed/self endpoints, avoids duplicate connection requests, requires user confirmation of the platform authentication code, and exposes byte payloads only after verification.

The adapter broadcasts encrypted envelopes to verified peers, tolerates partial endpoint failure, and uses a conservative 32 KiB encoded-payload limit. It is Android-only and depends on Google Play services Nearby.

### iOS Multipeer fallback

`IosMultipeerTransport` wraps the private `meshtalk_multipeer` Flutter plugin and Apple's Multipeer Connectivity framework.

The iOS path advertises and browses `meshtalk-chat`, derives a six-digit comparison code from stable device IDs and ephemeral nonces, delays invitation/acceptance until local approval, requires `MCSession` link encryption, and exposes reliable byte payloads only after verification.

The iOS runner is generated in CI and configured with Local Network usage, `_meshtalk-chat._tcp` Bonjour registration, Bluetooth usage descriptions, iOS 13, and the Keychain entitlement required by secure room storage.

### Shared storage and relay

`SqliteMessageStore` persists the encoded envelope together with sender label, direction, and delivery state. New message payloads are ciphertext. Message ID is the primary key, so retries and duplicate inbound events remain idempotent.

A relay-only device can forward an envelope without the corresponding room key. It sees routing metadata but cannot authenticate/decrypt the message text. Relay processing still decrements hop count, drops TTL-zero messages, and suppresses already-seen IDs.

## Room and message UI

The chat header shows the active room name, key fingerprint, and end-to-end encrypted status. The lock action lets the user:

- copy the active room code;
- paste and join a room code;
- create a new encrypted room.

Copying a room code places secret key material on the system clipboard. Share it deliberately and clear clipboard history where the operating system or keyboard retains copied content.

Each message displays one of these protection states:

- **end-to-end encrypted** — authenticated with the active room key;
- **legacy unencrypted history** — local plaintext created by an earlier build;
- **unable to authenticate** — stored encrypted content cannot be opened with the active room key.

## Diagnostics

The diagnostics dialog shows:

- current session state;
- XChaCha20-Poly1305 group E2EE status;
- active secure room and key fingerprint;
- active transport and transport ID;
- Bluetooth radio availability;
- connected peer and pending-verification counts;
- durable queued-message count;
- active transport payload limit;
- last refresh time;
- most recent transport or encryption error.

Diagnostics do not display room codes, room key bytes, message plaintext, ciphertext, or peer authentication tokens.

## Local profile

On first launch, MeshTalk generates a UUID device ID and short display name. The user can edit the display name without changing the device ID or room key. Profile values remain in `shared_preferences`; encrypted-room keys use platform secure storage.

No account, phone number, contacts access, or cloud profile is required.

## Durable queue recovery

- Outgoing plaintext is encrypted before its queued SQLite row is written.
- Only successful transport delivery changes an outgoing message to sent.
- Ciphertext queue entries survive process restart and retry when a peer connects.
- Legacy queued plaintext is migrated to the active encrypted room before restoration.
- Message IDs deduplicate restored queue entries, radio echoes, and cross-transport duplicates.
- Pending encrypted messages for an inactive room stay in SQLite and are restored when that room becomes active again.

The database remains schema version 1 because the existing envelope blob can carry either legacy plaintext or the versioned encrypted payload. Future schema changes must add explicit migration tests.

## Getting started

1. Install a current stable Flutter SDK with Dart 3.6 or newer.
2. Clone the repository.
3. Generate and configure native project folders:

   ```bash
   flutter create --platforms=android,ios .
   bash tool/configure_android_project.sh
   bash tool/configure_ios_project.sh
   ```

   The iOS script must run on macOS because it verifies generated property lists and entitlements with `PlistBuddy`.

4. Install dependencies and run checks:

   ```bash
   flutter pub get
   dart format lib packages test integration_test
   flutter analyze --fatal-infos
   flutter test
   ```

5. Run signed builds on physical devices for encryption, secure-storage, BLE, Nearby, Multipeer, permission, and lifecycle validation. Simulator compilation does not replace two-phone testing.

## Native security configuration

### Android

`tool/configure_android_project.sh`:

- sets `minSdk` to API 24;
- declares BLE, Wi-Fi, Nearby Wi-Fi, local-network, and bounded legacy permissions;
- does not request storage, contacts, SMS, camera, or background location;
- sets `android:allowBackup="false"` and `android:fullBackupContent="false"` so secure-storage ciphertext is not restored without device-bound key material.

### iOS

`tool/configure_ios_project.sh`:

- sets the iOS deployment target to 13.0;
- adds Local Network and Bluetooth usage descriptions;
- registers `_meshtalk-chat._tcp` under `NSBonjourServices`;
- creates `Runner.entitlements` with the application Keychain access group;
- assigns the entitlement file to generated Xcode build configurations;
- is idempotent and safe to rerun after native project generation.

## CI artifacts

The `Android APK` workflow generates/configures Android, compiles a release APK with development signing, creates a SHA-256 checksum, and uploads it for internal testing.

The `iOS Simulator` workflow runs on macOS, generates/configures iOS, resolves CocoaPods, compiles Swift and secure-storage plugins, builds an unsigned simulator app, creates a SHA-256 checksum, and uploads it. The artifact cannot be installed on a physical iPhone.

## Dependency notes

- `cryptography` 2.9.0 provides XChaCha20-Poly1305 and SHA-256 primitives.
- `flutter_secure_storage` 10.3.1 stores the versioned room-key ring through platform secure storage.
- `bluetooth_low_energy` 6.2.1 provides BLE central and peripheral roles on Android and iOS.
- `nearby_connections` 4.3.0 provides Android Nearby Connections.
- `meshtalk_multipeer` is the private Apple Multipeer Connectivity plugin.
- `shared_preferences` 2.5.3 stores non-sensitive profile preferences only.
- `sqflite` 2.4.1 stores encoded message envelopes and delivery state.

## Known limitations

- Shared-room encryption does not provide per-member identity verification, forward secrecy, post-compromise security, automatic key rotation, or member revocation.
- Anyone with the room code can read and create messages for that room.
- Existing legacy history remains plaintext in the local database and is labelled in the UI.
- The current room dialog can create or import rooms but does not yet provide a complete saved-room list, deletion, or member-management UI.
- Clipboard managers may retain copied room codes.
- Transport/routing metadata is not encrypted.
- Matching platform comparison codes verify a connection attempt, not either person's real-world identity.
- Platform fallbacks activate when BLE is unavailable; they do not currently start merely because BLE has zero peers.
- BLE and local-network transports are foreground-first; full background restoration remains future work.
- Symmetric BLE discovery can create more than one logical path; message-ID deduplication remains authoritative.
- Internet relay is not implemented.
- History has no retention, export, or delete controls.
- Signed physical-device verification on at least two phones per platform is required before release.

## Development process

- Never push feature work directly to `main`.
- Use Conventional Commits.
- Every user-facing change updates `CHANGELOG.md`.
- Every core/domain feature requires tests.
- Storage or encrypted payload changes require migration and tamper tests.
- Real-device changes require the checklist in `docs/manual-test-checklist.md`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development rules. The focused encryption validation plan is in [docs/pr9-validation-plan.md](docs/pr9-validation-plan.md).
