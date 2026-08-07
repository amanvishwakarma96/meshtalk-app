# MeshTalk

MeshTalk is an offline-first mobile chat application for nearby users. Its primary transport is Bluetooth Low Energy (BLE) mesh, with Android Nearby Connections and Apple Multipeer Connectivity fallbacks selected through a shared transport abstraction.

## Status

Phase 1 is under active development. MeshTalk creates a persistent local profile and Ed25519 signing identity, selects a nearby transport, stores encrypted history in SQLite, restores unsent messages after process restart, and relays signed ciphertext through the mesh protocol.

New messages use shared-room end-to-end encryption plus persistent device signatures. Android and iOS native builds compile in CI, but physical multi-device encryption, identity-change, transport, permission, secure-storage, and lifecycle validation is still required before release.

## Transport priority

1. BLE mesh
2. Android Nearby Connections on Android
3. Apple Multipeer Connectivity on iOS
4. Clearly labelled optional internet relay in a future milestone
5. Actionable no-transport state

`TransportManager` chooses and hot-swaps `ChatTransport` implementations without changing message identity, room identity, storage, relay TTL, signature semantics, or deduplication behavior. A higher-priority transport must activate successfully before a working fallback is disconnected.

## Security model at a glance

MeshTalk uses three separate security concepts:

1. **Room key** — a shared 256-bit key encrypts message content for every member possessing the room code.
2. **Device signing identity** — each stable device ID has a persistent Ed25519 key pair used to sign new encrypted messages.
3. **Transport verification** — Android Nearby and iOS Multipeer comparison codes verify one platform connection attempt before bytes are exposed to the app.

These mechanisms solve different problems. Sharing a room code does not verify a person's identity. A transport comparison code does not replace a persistent signing fingerprint. A first-seen signing key is pinned locally but should be compared through a trusted independent channel before being marked verified.

## End-to-end encrypted rooms

MeshTalk creates a local encrypted room on first launch. A room contains:

- a random 256-bit symmetric key;
- a random room identifier;
- a human-readable local name;
- a short fingerprint derived from the room key.

New message text is encrypted with XChaCha20-Poly1305 before it enters SQLite or any BLE, Nearby, or Multipeer transport.

The authenticated immutable envelope fields are:

- message ID;
- sender device ID;
- room ID;
- UTC timestamp.

The relay hop limit is intentionally excluded so an intermediate mesh node can decrement TTL without possessing the room key. Message IDs and the seen-message cache remain authoritative for replay and duplicate suppression.

### Joining a room

The room owner copies a versioned `MT1` room code and shares it through a trusted channel. The code contains the room ID, room key, room name, and a checksum that detects modification before import.

Anyone who obtains the room code becomes a full content-encryption member. They can decrypt matching ciphertext and create messages under a new signing identity. Treat the code like a password or recovery key.

Room keys are stored through `flutter_secure_storage`, using platform secure-storage facilities. Corrupt secure-room storage fails initialization instead of silently replacing keys.

## Authenticated device identities

Each installation generates an Ed25519 signing identity associated with its stable local device ID. The signing private key is stored through the same platform secure-storage boundary but is independent of the shared room key.

### Signed payload protocol version 2

A new encrypted payload contains:

- frame magic, protocol version, and algorithm identifier;
- room-key identifier;
- sender identity-key identifier;
- sender Ed25519 public key;
- 24-byte XChaCha20 nonce;
- Poly1305 authentication tag;
- 64-byte Ed25519 signature;
- ciphertext.

The Ed25519 signature covers the immutable envelope metadata, room-key identifier, identity-key identifier, public key, nonce, authentication tag, and ciphertext. Changing the claimed sender ID, signed metadata, public key, signature, or protected content causes rejection before the message enters visible history.

The private signing key is never included in room codes, SQLite envelopes, transport frames, diagnostics, or clipboard output.

### Trust on first use

The first valid signing key observed for a sender device ID is pinned locally as **First seen**. Later messages with the same key are accepted under that trust state.

Users can open **Device identities**, compare the short fingerprint through a trusted independent channel, and mark it **Verified**. That verification is a local user decision; MeshTalk does not claim that a display name, device ID, or first-seen fingerprint automatically proves a person's real-world identity.

Trust decisions are associated with the stable device ID and persist across rooms. Joining a different room does not rotate the local signing identity.

### Identity changes

When a different valid key claims an already pinned device ID:

- the old key remains trusted;
- the new fingerprint is stored as pending;
- the new message is blocked from visible history and persistence;
- diagnostics and the security banner report the change;
- opaque ciphertext relay may continue independently.

The user can keep the old key or explicitly approve the replacement. An approved replacement returns to **First seen** and should be compared again before it is marked verified.

MeshTalk currently retains the most recently blocked envelope per changed sender for possible release after approval. Identity-change handling is not a complete group membership or key-transparency protocol.

## Security boundary

This milestone protects message content from transports and relay-only peers without the room key, and prevents a room-key holder from silently impersonating an already pinned device ID without that device's Ed25519 private key.

It does **not** provide:

- forward secrecy;
- post-compromise security;
- automatic signing-key or room-key rotation;
- authenticated group membership;
- member removal or revocation;
- a public key transparency service;
- proof of a person's real-world identity;
- protection after the room code, device private key, or trusted comparison channel is compromised.

A room-key holder can still introduce a new first-seen sender identity. Users must compare fingerprints independently before treating an identity as verified.

Transport and routing metadata remains visible to nearby participants and relays, including message IDs, sender device IDs, room IDs, timestamps, hop limits, payload lengths, sender public keys, and transport-level peer information. Message text remains ciphertext.

## Legacy history and migration

Messages created before encrypted rooms remain readable from local SQLite and are labelled **legacy unencrypted history**. They are not retroactively encrypted in place.

Protocol-version-1 encrypted history from PR #9 remains locally readable and is labelled **unsigned legacy sender**. Version-1 payloads received from the network are rejected because they do not authenticate a persistent sender identity.

Before queue restoration:

- pending plaintext is encrypted and signed with the active room and local device identity;
- pending version-1 ciphertext is decrypted locally, then re-encrypted and signed as protocol version 2;
- already valid local protocol-version-2 queue entries are restored unchanged.

Wrong-key, malformed, tampered, unsigned-network, and invalid-signature payloads are never displayed or persisted as received messages.

Loss of the room key makes encrypted history unreadable. Loss of the signing key creates a new identity and can trigger identity-change warnings on peers. Keep the room code securely when portable content recovery is required; the room code does not recover the old signing identity.

## Architecture

```text
lib/
  core/
    ble/                 # dual-role radio, frame codec, relay and reassembly
    profile/             # stable local device ID and editable name
    permissions/         # centralized runtime permission policy
    security/            # rooms, AEAD, Ed25519 identities and trust store
    storage/             # SQLite encrypted envelopes and durable queue
    transport/           # BLE, Android Nearby, iOS Multipeer and selection
  features/
    chat/
      data/              # signed encrypted multi-transport orchestration
      domain/            # immutable UI/session and diagnostics models
      presentation/      # room, identity, verification and diagnostics UI
  app.dart
  app_providers.dart
  main.dart

packages/
  meshtalk_multipeer/    # private Flutter plugin and native Swift bridge
```

### Encryption and identity path

`MessageProtector` uses XChaCha20-Poly1305 for content and Ed25519 for sender authentication. `SecureRoomCodeCodec` validates offline room codes. `SecureRoomStore` maintains the encrypted-room keyring. `DeviceIdentityStore` maintains one persistent local signing identity. `IdentityTrustStore` maintains pinned peer keys, verification state, and pending changes.

`ChatSession`:

- encrypts and signs outgoing text before persistence and transport delivery;
- stores new outgoing and authenticated incoming payloads as ciphertext;
- verifies the signature before decrypting/displaying a network message;
- pins first-seen identities and labels their messages;
- blocks changed identities until explicit approval;
- rejects malformed, wrong-key, unsigned-network, invalid-signature, and tampered payloads;
- labels legacy local plaintext and unsigned version-1 history;
- upgrades queued legacy payloads before transmission;
- relays ciphertext for other rooms without decrypting, displaying, or trusting it;
- records transport, encryption, and identity failures in local diagnostics.

### BLE path

`BluetoothLowEnergyMeshRadio` advertises the MeshTalk GATT service, scans for the same service, connects as a central, accepts writes as a peripheral, sends notifications, and reports negotiated frame limits. `BleTransport` converts signed encrypted envelopes into compact BLE frames and reassembles inbound chunks.

### Android Nearby fallback

`AndroidNearbyTransport` wraps Android Nearby Connections with the P2P cluster strategy. It starts only after version-appropriate permissions, rejects malformed/self endpoints, avoids duplicate connection requests, requires user confirmation of the platform authentication code, and exposes byte payloads only after verification.

The adapter broadcasts signed encrypted envelopes to verified peers, tolerates partial endpoint failure, and uses a conservative 32 KiB encoded-payload limit. It is Android-only and depends on Google Play services Nearby.

### iOS Multipeer fallback

`IosMultipeerTransport` wraps the private `meshtalk_multipeer` Flutter plugin and Apple's Multipeer Connectivity framework.

The iOS path advertises and browses `meshtalk-chat`, derives a six-digit comparison code from stable device IDs and ephemeral nonces, delays invitation/acceptance until local approval, requires `MCSession` link encryption, and exposes reliable byte payloads only after verification.

The iOS runner is generated in CI and configured with Local Network usage, `_meshtalk-chat._tcp` Bonjour registration, Bluetooth usage descriptions, iOS 13, and the Keychain entitlement required by room and signing-key storage.

### Shared storage and relay

`SqliteMessageStore` persists the encoded envelope together with sender label, direction, and delivery state. New message payloads are signed ciphertext. Message ID is the primary key, so retries and duplicate inbound events remain idempotent.

A relay-only device can forward an envelope without the corresponding room key. It sees routing and signing metadata but cannot decrypt message text. Relay processing decrements hop count, drops TTL-zero messages, and suppresses already-seen IDs without changing signed content.

## Room, identity, and message UI

The chat header shows the active room name, E2EE status, and whether any identity changes are blocked.

The lock action lets the user:

- copy the active room code;
- paste and join a room code;
- create a new encrypted room.

Copying a room code places secret key material on the system clipboard. Share it deliberately and clear clipboard history where the operating system or keyboard retains copied content.

The identity action lets the user:

- view this device's signing fingerprint;
- inspect first-seen and verified peer identities;
- mark a compared fingerprint verified;
- review and approve or reject a changed key.

Message rows distinguish:

- **E2EE · signed by this device**;
- **E2EE · first-seen sender identity**;
- **E2EE · verified sender identity**;
- **encrypted · unsigned legacy sender**;
- **legacy unencrypted history**;
- **unable to authenticate**.

## Diagnostics

The diagnostics dialog shows:

- current session state;
- XChaCha20-Poly1305 group E2EE;
- Ed25519 signed protocol version 2;
- active room and room fingerprint;
- local signing fingerprint;
- pinned-identity and pending-change counts;
- active transport and transport ID;
- Bluetooth availability;
- connected peer, transport-verification, and durable queue counts;
- active payload limit and last refresh time;
- most recent transport, encryption, signature, or identity error.

Diagnostics do not display room codes, room keys, private signing keys, message plaintext, ciphertext, or transport authentication tokens.

## Local profile

On first launch, MeshTalk generates a UUID device ID and short display name. It also generates a separate Ed25519 signing identity bound to the device ID.

The user can edit the display name without changing device ID, room key, signing fingerprint, trust records, or history. Profile values remain in `shared_preferences`; secret room and signing material use platform secure storage.

No account, phone number, contacts access, or cloud profile is required.

## Durable queue recovery

- Outgoing plaintext is encrypted and signed before its queued SQLite row is written.
- Only successful transport delivery changes an outgoing message to sent.
- Signed ciphertext queue entries survive process restart and retry when a peer connects.
- Legacy plaintext and version-1 ciphertext are upgraded before restoration.
- Message IDs deduplicate restored queue entries, radio echoes, and cross-transport duplicates.
- Pending encrypted messages for an inactive room stay in SQLite and are restored when that room becomes active again.

The database remains schema version 1 because the envelope blob can carry plaintext legacy rows, version-1 ciphertext, or signed version-2 payloads. Future schema changes must add explicit migration tests.

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

5. Run signed builds on physical devices for room encryption, identity pinning/change handling, secure storage, BLE, Nearby, Multipeer, permissions, relay, and lifecycle validation. Simulator compilation does not replace multi-phone testing.

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

- `cryptography` 2.9.0 provides XChaCha20-Poly1305, Ed25519, and SHA-256 primitives.
- `flutter_secure_storage` 10.3.1 stores room keys, local signing keys, and identity trust records through platform secure storage.
- `bluetooth_low_energy` 6.2.1 provides BLE central and peripheral roles on Android and iOS.
- `nearby_connections` 4.3.0 provides Android Nearby Connections.
- `meshtalk_multipeer` is the private Apple Multipeer Connectivity plugin.
- `shared_preferences` 2.5.3 stores non-sensitive profile preferences only.
- `sqflite` 2.4.1 stores encoded message envelopes and delivery state.

## Known limitations

- Shared-room encryption and persistent signatures do not provide forward secrecy or post-compromise security.
- Anyone with the room code can read content and create messages under a new first-seen identity.
- First-seen pinning and locally verified fingerprints do not prove real-world identity without a trustworthy comparison channel.
- There is no authenticated group-membership, member-revocation, key-transparency, or automatic key-rotation protocol.
- The identity UI does not yet provide trust deletion/reset, export, or a complete member list scoped to one room.
- Only the most recently blocked changed-key envelope per sender is retained for release after approval.
- Existing plaintext and version-1 encrypted history remain local legacy content and are labelled in the UI.
- The room dialog can create/import rooms but does not provide a complete saved-room list, deletion, or member-management UI.
- Clipboard managers may retain copied room codes.
- Transport/routing/signing metadata is not encrypted.
- Platform comparison codes verify a connection attempt, not persistent identity or real-world identity.
- Platform fallbacks activate when BLE is unavailable; they do not start merely because BLE has zero peers.
- BLE and local-network transports are foreground-first; full background restoration remains future work.
- Symmetric BLE discovery can create more than one logical path; message-ID deduplication remains authoritative.
- Internet relay is not implemented.
- History has no retention, export, or delete controls.
- Signed physical-device verification on multiple phones is required before release.

## Development process

- Never push feature work directly to `main`.
- Use Conventional Commits.
- Every user-facing change updates `CHANGELOG.md`.
- Every core/domain feature requires tests.
- Storage or encrypted payload changes require migration, signature, and tamper tests.
- Real-device changes require `docs/manual-test-checklist.md`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development rules. The focused identity validation plan is in [docs/pr10-validation-plan.md](docs/pr10-validation-plan.md).
