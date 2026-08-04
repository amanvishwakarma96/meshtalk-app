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

### Changed

- Replaced the central-only `flutter_blue_plus` dependency with MIT-licensed `bluetooth_low_energy`, which supports both central and peripheral roles.
- Android project configuration now enforces API 24 and declares scan, connect, advertise, and legacy discovery permissions.

### Fixed
