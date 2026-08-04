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

### Changed

- Replaced the central-only `flutter_blue_plus` dependency with MIT-licensed `bluetooth_low_energy`, which supports both central and peripheral roles.
- Android project configuration now enforces API 24 and declares scan, connect, advertise, and legacy discovery permissions.
- The app now launches the live session-backed chat page instead of the static chat shell.
- `TransportManager` now emits successful-send events used to update durable delivery state.

### Fixed

- Queued messages now retry when the currently selected transport gains a peer, without requiring a transport switch.
- Locally originated message IDs are marked as seen so radio echoes are not shown or relayed again.
- Relaying an incoming envelope no longer changes its local delivery label from received to sent.
- Restored queued messages are deduplicated before entering the in-memory transport queue.
