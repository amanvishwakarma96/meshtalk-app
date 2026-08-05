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

### Changed

- Replaced the central-only `flutter_blue_plus` dependency with MIT-licensed `bluetooth_low_energy`, which supports both BLE central and peripheral roles.
- Android project configuration now enforces API 24 and declares BLE, Wi-Fi state, Nearby Wi-Fi, legacy location, and local-network permissions without storage access.
- The app now launches the live session-backed chat page instead of the static chat shell.
- `TransportManager` now emits successful-send events used to update durable delivery state.
- `TransportManager` now continues to lower-priority transports when a higher-priority transport fails to activate and preserves a working fallback when an upgrade fails.
- `ChatSession` now consumes peer and message streams from every registered transport while keeping BLE as the first priority.
- Android Nearby peers are now shown as connected only after the user confirms that the authentication codes match on both phones.

### Fixed

- Queued messages now retry when the currently selected transport gains a peer, without requiring a transport switch.
- Locally originated message IDs are marked as seen so radio echoes are not shown or relayed again.
- Relaying an incoming envelope no longer changes its local delivery label from received to sent.
- Restored queued messages are deduplicated before entering the in-memory transport queue.
- Duplicate or stale Nearby connection callbacks no longer bypass the pending verification state.
