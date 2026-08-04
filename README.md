# MeshTalk

MeshTalk is an offline-first mobile chat application for nearby users. Its primary transport is Bluetooth Low Energy (BLE) mesh, with local Wi-Fi and optional internet relay fallbacks selected through a transport abstraction.

## Status

Phase 1 foundation is under active development. This repository currently contains the Flutter application skeleton, transport contracts, mesh message protocol primitives, tests, CI, and release documentation. Physical BLE and local-network adapters are implemented incrementally behind the same contracts.

## Transport priority

1. BLE mesh
2. Local Wi-Fi / Nearby Connections / Multipeer Connectivity
3. Clearly labelled internet relay
4. Actionable no-transport state

The chat feature must not depend directly on a BLE plugin. `TransportManager` chooses and hot-swaps `ChatTransport` implementations without changing message identity or relay semantics.

## Security notice

MeshTalk is **not end-to-end encrypted yet**. BLE pairing/bonding may protect an individual radio link, but relayed message payloads remain readable at the application layer by intermediate peers. Do not use the current build for sensitive communications. This warning must remain visible until message-level encryption ships.

## Architecture

```text
lib/
  core/
    ble/                 # envelope, relay, dedup, chunking and reassembly
    permissions/         # centralized runtime permission policy
    storage/             # local persistence adapters
    transport/           # ChatTransport and TransportManager
  features/
    chat/
    diagnostics/
    ble_console/
  app.dart
  main.dart
test/
  unit/
  widget/
  integration/
integration_test/
```

## Getting started

1. Install a current stable Flutter SDK with Dart 3.6 or newer.
2. Clone the repository.
3. Generate native project folders if they are not present:

   ```bash
   flutter create --platforms=android,ios .
   ```

4. Install dependencies and run checks:

   ```bash
   flutter pub get
   flutter analyze
   flutter test
   ```

5. Run the app on a physical Android or iOS device. BLE behavior cannot be validated reliably on a simulator.

## Android APK artifacts

The `Android APK` GitHub Actions workflow runs for Android-relevant pull requests, pushes to `main`, and manual workflow dispatches. It:

- generates the Android Flutter scaffold on the runner when the repository does not contain one yet;
- builds `flutter build apk --release`;
- uses the GitHub Actions run number as Android `versionCode`;
- uploads the APK and `SHA256SUMS.txt` as a downloadable workflow artifact for 14 days.

Open the relevant Actions run and download `meshtalk-android-apk-<run-number>` from its **Artifacts** section.

The generated APK currently uses the default Flutter development signing configuration and is intended for internal installation/testing only. A Play Store build requires maintainer-approved release signing secrets and an Android App Bundle workflow.

## Dependency notes

- `flutter_blue_plus` is the intended BLE adapter dependency. Review its current distribution/licensing terms before publishing binaries.
- `nearby_connections` 4.3.0 exposes Android Nearby Connections, not iOS Multipeer Connectivity. MeshTalk must use a separate iOS platform-channel adapter for equivalent local-network fallback rather than claiming cross-platform behavior from this package.
- Permissions are limited to Bluetooth scan/connect, foreground location where required for discovery, local-network access, and notifications. Camera, contacts, SMS, file storage, and background/always location are prohibited without maintainer approval.

## Development process

- Never push feature work directly to `main`.
- Use Conventional Commits.
- Every user-facing change updates `CHANGELOG.md`.
- Every core/domain feature requires tests.
- Real-device changes to `core/ble/` require the manual checklist in `docs/manual-test-checklist.md`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch, PR, testing, and release rules.
