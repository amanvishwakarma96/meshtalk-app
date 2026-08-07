# PR #10 authenticated-device-identity validation plan

This plan validates the Ed25519 sender-identity milestone independently from the broader release checklist.

## Security claim under test

A valid protocol-version-2 message must satisfy both layers:

1. XChaCha20-Poly1305 authenticates and decrypts the room content with the shared room key.
2. Ed25519 authenticates the claimed sender device ID, immutable envelope metadata, encrypted frame header, and ciphertext with the sender's persistent signing key.

A room-key holder may create a new sender identity, but cannot silently replace an already pinned device ID without triggering an identity-change warning. First-seen trust is not proof of a person's real-world identity.

## Automated gates

- [ ] `dart format lib packages test integration_test` produces no diff.
- [ ] `flutter analyze --fatal-infos` reports zero issues.
- [ ] All existing transport, storage, relay, encryption, session, integration, and widget tests remain green.
- [ ] Device identity store creates a 32-byte Ed25519 public/private key pair and reloads the same key.
- [ ] Corrupt signing-key storage and a device-ID mismatch fail closed.
- [ ] Signed version-2 round trip returns the original plaintext and sender public key.
- [ ] Plaintext bytes do not appear as a contiguous sequence in the protected payload.
- [ ] Sender ID, message ID, room ID, timestamp, identity key ID, public key, nonce, MAC, signature, and ciphertext tampering are rejected.
- [ ] Relay hop-limit decrement remains valid because hop limit is intentionally excluded from the signature and AEAD associated data.
- [ ] First valid key for a sender device ID is pinned as First seen.
- [ ] Repeated messages from the same key retain the trust decision.
- [ ] Marking a fingerprint verified persists across trust-store reload.
- [ ] A different key for the same device ID is staged without replacing the current key.
- [ ] Accepting the pending key installs it as First seen and clears prior verification.
- [ ] Rejecting the pending key preserves the current key.
- [ ] Live changed-key messages are blocked from display/storage while relay remains possible.
- [ ] Approving a pending key releases the most recently blocked message from that sender.
- [ ] Protocol-version-1 encrypted history is locally readable as unsigned legacy content.
- [ ] Protocol-version-1 network payloads are rejected.
- [ ] Queued plaintext and queued protocol-version-1 ciphertext are upgraded to signed version 2 before transport restoration.
- [ ] Android release APK compiles with secure storage and backup hardening.
- [ ] iOS simulator app compiles with Keychain entitlement, CocoaPods, and Swift plugins.

## Two-device physical test

Use two clean physical devices, A and B, with the same room code.

1. Record A and B's local signing fingerprints.
2. Send A → B over BLE and verify B labels A First seen.
3. Compare A's fingerprint independently and mark it verified on B.
4. Send another A → B message and verify B labels it verified sender identity.
5. Repeat B → A.
6. Restart both devices and verify fingerprints/trust decisions persist.
7. Rename both local profiles and verify fingerprints remain unchanged.
8. Switch rooms and verify the same device signing fingerprints remain visible.
9. Repeat over Android Nearby or iOS Multipeer and confirm transport comparison codes remain separate from signing fingerprints.

## Identity-change simulation

Use a controlled development build or cleared signing-key storage while preserving the test device ID.

1. Establish and verify A's original key on B.
2. Replace A's local signing key while preserving A's stable device ID.
3. Send A → B.
4. Confirm B does not display or persist the new message in visible history.
5. Confirm B shows the old and pending fingerprints and records a local identity error.
6. Choose Keep old key and confirm later old-key traffic remains trusted.
7. Repeat the replacement, choose Approve new key, and confirm the blocked message appears as First seen.
8. Compare the new fingerprint and mark it verified again.

## Three-device relay test

Use A and C in the same room, with B acting as a relay that does not possess the room key.

1. Send signed ciphertext A → B → C.
2. Confirm B does not display content and does not create a trust record for A in an inactive room.
3. Confirm B decrements hop limit without modifying signed/authenticated content.
4. Confirm C validates A's signature, pins A's key, decrypts content, and displays exactly once.
5. Repeat with a changed A key and verify C blocks local display while B still relays opaque ciphertext.

## Migration test

1. Install the PR #9 build and queue an encrypted message while no peer is connected.
2. Upgrade to PR #10 without clearing app data.
3. Confirm history labels the old payload unsigned legacy sender.
4. Confirm the queued envelope is rewritten to signed protocol version 2 before the first transport retry.
5. Connect a peer and confirm exactly-once delivery with the current local signing fingerprint.
6. Force-close during the process and confirm restart does not duplicate the row or queue entry.

## Release blockers

Do not describe this milestone as release-ready when any of these remain unresolved:

- signatures are not validated before display/persistence;
- identity changes replace pinned keys automatically;
- fingerprint comparison is presented as automatic real-world identity proof;
- protocol-version-1 payloads are accepted from the network;
- queued legacy payloads leave the device unsigned;
- private signing keys appear in logs, diagnostics, SQLite, room codes, clipboard output, or transport payloads;
- Android/iOS secure-storage compilation fails;
- signed physical-device testing has not been completed.
