# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [Unreleased]

### Added

- Initial Flutter project foundation and GitHub Actions CI.
- Transport-agnostic chat contracts and selection manager.
- BLE mesh envelope, chunking, reassembly, deduplication, and relay primitives.
- Unit, widget, and mocked two-peer integration tests.
- Real-device release verification checklist.
- Android release APK workflow with downloadable artifact and SHA-256 checksum.
- Dual-role BLE radio adapter for advertising, scanning, GATT writes, notifications, peer tracking, and MTU-aware frame delivery.
- Compact binary BLE chunk frame codec and transport-level unit tests.
- Persistent local device identity and generated display name with no account requirement.
- Runtime chat session wiring for BLE authorization, live peer state, queued sends, relay decisions, and actionable recovery UI.
- SQLite-backed local message history with deterministic room ordering.
- Restart-safe restoration and retry of queued outbound messages.
- Editable local display name with BLE session restart and re-advertising.
- In-memory SQLite schema tests and restart-recovery session tests.
- Android-only Nearby Connections fallback using the P2P cluster strategy and byte payloads.
- Stable MeshTalk endpoint identities, deterministic connection initiation, invalid-peer rejection, and fallback-specific UI warnings.
- Android Nearby transport tests for authorization, discovery, connection, broadcast delivery, malformed payloads, and cleanup.
- User-confirmed Android Nearby authentication-code verification before connection acceptance or payload delivery.
- Transport diagnostics dialog for radio state, active transport, peer count, queued messages, payload limit, refresh time, and last error.
- Foreground-resume transport refresh with serialized recovery requests.
- Private iOS Flutter plugin backed by Apple's Multipeer Connectivity framework.
- Verified iOS local-network fallback with six-digit comparison codes, required `MCSession` link encryption, reliable byte delivery, and shared queue/relay handling.
- Repeatable iOS runner configuration for Local Network, Bonjour, and Bluetooth usage descriptions.
- macOS GitHub Actions workflow that compiles the Swift bridge and produces a downloadable iOS simulator artifact with checksum.
- iOS transport tests for availability, verification, peer publication, message decoding, broadcast failures, payload bounds, and runtime diagnostics.
- Shared-key encrypted rooms with random 256-bit keys and XChaCha20-Poly1305 authenticated encryption.
- Versioned encrypted payload frames with room-key identifiers, 24-byte nonces, authentication tags, and immutable envelope metadata bound as associated data.
- Offline copy-and-paste encrypted-room codes with checksum validation and short key fingerprints.
- Platform secure storage for encrypted-room keyrings through `flutter_secure_storage`.
- Encrypted-room management UI for copying the active room code, joining a room, and creating a new room.
- Per-message encrypted, legacy-unencrypted, and unable-to-authenticate indicators.
- Encryption details and room fingerprints in local diagnostics.
- Cryptography, secure-room codec, secure-storage, migration, tamper-rejection, ciphertext-relay, session, and widget regression tests.

### Changed

- Replaced the central-only `flutter_blue_plus` dependency with MIT-licensed `bluetooth_low_energy`, which supports both BLE central and peripheral roles.
- Android project configuration now enforces API 24 and declares BLE, Wi-Fi state, Nearby Wi-Fi, legacy location, and local-network permissions without storage access.
- Android application backup is disabled so secure-storage ciphertext is not restored without its device-bound key material.
- iOS project configuration now creates a repeatable Keychain entitlement for encrypted-room key storage.
- The app now launches the live session-backed chat page instead of the static chat shell.
- `TransportManager` now emits successful-send events used to update durable delivery state.
- `TransportManager` now continues to lower-priority transports when a higher-priority transport fails to activate and preserves a working fallback when an upgrade fails.
- `TransportManager` now re-invokes idempotent activation during refresh so an active native transport can recover after a runtime failure.
- `ChatSession` now consumes peer and message streams from every registered transport while keeping BLE as the first priority.
- `ChatSession` now reports platform-specific Android Nearby or iOS Multipeer status and records native runtime errors in transport diagnostics.
- `ChatSession` now encrypts new message payloads before SQLite persistence or transport delivery and decrypts only authenticated messages for the active room.
- Intermediate peers can relay ciphertext for rooms they have not joined while retaining normal TTL and message-ID deduplication.
- Pending legacy plaintext messages are migrated to authenticated ciphertext before they enter the transport queue.
- Existing plaintext history remains readable locally but is explicitly labelled as legacy unencrypted history.
- Android Nearby peers are now shown as connected only after the user confirms that the authentication codes match on both phones.

### Fixed

- Queued messages now retry when the currently selected transport gains a peer, without requiring a transport switch.
- Locally originated message IDs are marked as seen so radio echoes are not shown or relayed again.
- Relaying an incoming envelope no longer changes its local delivery label from received to sent.
- Restored queued messages are deduplicated before entering the in-memory transport queue.
- Duplicate or stale Nearby connection callbacks no longer bypass the pending verification state.
- Tampered ciphertext, immutable-metadata changes, wrong room keys, and unauthenticated network plaintext are rejected before entering visible history.
- Corrupt secure-room storage fails initialization instead of silently generating replacement key material.
