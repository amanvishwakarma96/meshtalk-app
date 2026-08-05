# PR 9 validation plan — end-to-end encrypted rooms

## Automated gates

- [ ] Resolve dependencies on the Dart 3.6 baseline.
- [ ] Format `lib`, `packages`, `test`, and `integration_test` with no diff.
- [ ] Run `flutter analyze --fatal-infos` with zero issues.
- [ ] Run all unit, widget, SQLite, transport, session, relay, and mocked integration tests.
- [ ] Generate/configure Android and compile a release APK.
- [ ] Verify Android backup is disabled in the generated manifest.
- [ ] Generate/configure iOS and validate the Keychain entitlement.
- [ ] Resolve CocoaPods and compile all Swift/secure-storage plugins.
- [ ] Build and package an unsigned iOS simulator app.
- [ ] Produce SHA-256 checksums and upload both platform artifacts.

## Cryptographic invariants

- [ ] Every new message uses a fresh XChaCha20-Poly1305 nonce.
- [ ] Room keys contain exactly 32 random bytes.
- [ ] Message ID, sender ID, room ID, and timestamp are authenticated as associated data.
- [ ] Hop limit can be decremented by a relay without invalidating the destination authentication tag.
- [ ] Ciphertext/tag mutation fails authentication.
- [ ] Immutable-metadata mutation fails authentication.
- [ ] A different room key is rejected before plaintext is exposed.
- [ ] Network plaintext is rejected for secure-room delivery.
- [ ] Legacy plaintext is allowed only for explicit local-history reads and queue migration.

## Persistence and migration invariants

- [ ] New SQLite rows contain ciphertext rather than visible message text.
- [ ] Existing legacy history remains readable and visibly labelled.
- [ ] Legacy queued plaintext is rewritten to the active room before transport restoration.
- [ ] Ciphertext remains stable across process restart.
- [ ] Corrupt secure-room key storage fails closed.
- [ ] Export/import reproduces identical room ID, key ID, key bytes, and fingerprint.
- [ ] Re-import does not create duplicate secure-room entries.

## Relay invariants

- [ ] A member destination can decrypt after one or more relay TTL decrements.
- [ ] A non-member relay forwards ciphertext without displaying or persisting plaintext.
- [ ] Duplicate message IDs are not delivered or relayed repeatedly.
- [ ] TTL-zero envelopes are dropped.

## UI and disclosure invariants

- [ ] The chat banner shows active room name, fingerprint, and group E2EE status.
- [ ] Room-code UI warns that possession grants read/send access.
- [ ] Encrypted, legacy, and unable-to-authenticate message states are distinct.
- [ ] Diagnostics show algorithm, room, fingerprint, and local failures without secret material.
- [ ] Documentation states metadata exposure and missing forward secrecy/member revocation.

## Manual release boundary

Automated tests and simulator builds do not prove device secure-storage behavior or physical transport interoperability. Complete `docs/manual-test-checklist.md` on signed builds before release. In particular, verify Keychain/Keystore persistence, room-code recovery, two-device decryption, wrong-room isolation, three-device ciphertext relay, tamper rejection, platform permissions, and lifecycle recovery.
