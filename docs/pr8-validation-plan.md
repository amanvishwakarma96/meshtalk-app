# PR 8 validation plan: iOS Multipeer fallback

This milestone adds an iOS local-network transport using Apple's Multipeer Connectivity framework. BLE remains first priority. The iOS fallback is eligible only on iOS and shares the existing message envelope, durable queue, relay, deduplication, verification, and diagnostics pipeline.

## Automated gates

- Resolve the local `meshtalk_multipeer` Flutter plugin on Linux, Android, and macOS runners.
- Verify Dart formatting across `lib`, `packages`, `test`, and `integration_test`.
- Run `flutter analyze --fatal-infos` with zero issues.
- Run all unit, widget, SQLite, transport, session, relay, and mocked integration tests.
- Build the Android release APK to prove the iOS-only path plugin does not break Android packaging.
- Generate the iOS runner on macOS when it is not stored in the repository.
- Apply `NSLocalNetworkUsageDescription`, `NSBonjourServices`, Bluetooth descriptions, and iOS 13 deployment settings.
- Compile the Swift plugin and build an unsigned simulator application.
- Generate SHA-256 checksums and upload both platform artifacts.

## Physical two-iPhone checks

- Install a signed development build on two physical iPhones.
- Grant Local Network and Bluetooth permissions only when prompted.
- Turn BLE off or make it unavailable so the Multipeer fallback becomes active.
- Confirm both phones display the same six-digit comparison code.
- Approve on both phones and verify the peer appears only after both approvals.
- Reject on either phone and verify no peer or payload stream is exposed.
- Send messages in both directions and verify exactly-once display.
- Queue a message with no peer, restart the app, reconnect, and verify one delivery.
- Exercise disconnect/reconnect, foreground/background transitions, and profile rename.
- Verify diagnostics show `ios-multipeer`, peer count, payload limit, queue count, and native errors.
- Restore BLE and confirm the manager upgrades without losing history or queued messages.

## Security boundary

The six-digit comparison code binds both users to the same discovery/invitation attempt, and `MCSession` is configured with required link encryption. This milestone does not implement message-level end-to-end encryption and does not establish a real-world identity for either peer.

## Artifact boundary

The macOS workflow produces an unsigned simulator build. It proves Swift compilation and plugin registration, but it cannot be installed on a physical iPhone and does not replace signed two-device testing.
