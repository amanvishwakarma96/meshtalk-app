# Manual two-device verification

Run this checklist on physical phones before every release and after changes to encryption, signing identities, secure storage, trust decisions, room codes, BLE, Android Nearby, iOS Multipeer, transport selection, profile, diagnostics, lifecycle, or storage behavior.

## Setup

- [ ] Fresh install on both devices.
- [ ] Record OS version, phone model, Google Play services version where applicable, app version, and build number.
- [ ] Grant only the permissions required by each tested path.
- [ ] Confirm the active encrypted-room name and end-to-end encrypted banner are visible.
- [ ] Open Device identities and record each phone's local signing fingerprint.
- [ ] Confirm diagnostics do not expose the room code, full room key, private signing key, plaintext, ciphertext, or peer authentication token.

## Encrypted room creation and sharing

- [ ] The first launch creates one encrypted room and keeps the same room ID, room fingerprint, and history after restart.
- [ ] Creating a room generates a different room ID, room fingerprint, and room code.
- [ ] Room names shorter than 2 or longer than 32 characters are rejected.
- [ ] Copying the room code places one complete `MT1` code on the clipboard.
- [ ] Modifying any room-code character causes checksum or format rejection.
- [ ] Pasting the valid code on a second device imports the same room ID, name, fingerprint, and key.
- [ ] Re-importing the same room does not duplicate its secure-storage entry.
- [ ] A room ID already stored with different key material is rejected.
- [ ] The room dialog warns that anyone with the code can read and send messages.
- [ ] Clipboard history is cleared manually after sharing on keyboards or operating systems that retain copied secrets.

## Persistent device signing identity

- [ ] First launch generates one Ed25519 signing identity independently from the room key.
- [ ] Local identity fingerprint remains identical after app restart, profile rename, room change, and transport switch.
- [ ] Editing the display name does not rotate the signing key or change the device ID.
- [ ] Joining another room retains the same device signing fingerprint.
- [ ] Android restart preserves the signing identity through secure storage.
- [ ] iOS restart preserves the signing identity through Keychain storage.
- [ ] Corrupt signing-key storage fails initialization rather than silently replacing the identity.
- [ ] Secure storage containing a signing key for another stable device ID is rejected.
- [ ] Uninstall/reinstall behavior is recorded separately for every tested OS version.

## Signed message protocol version 2

- [ ] Every new outgoing message is shown as E2EE and signed by this device.
- [ ] The transport payload contains protocol version 2, a sender public key, an identity-key fingerprint, and an Ed25519 signature.
- [ ] The SQLite envelope payload contains neither visible plaintext nor private signing-key material.
- [ ] A matching-room recipient validates the signature and displays the message exactly once.
- [ ] Changing the sender device ID causes signature rejection.
- [ ] Changing message ID, room ID, or timestamp causes signature/authentication rejection.
- [ ] Changing the identity-key ID or public key causes identity validation failure.
- [ ] Changing the signature, ciphertext, nonce, authentication tag, or authenticated header causes rejection.
- [ ] A device with another room key does not display or persist the payload as a received message.
- [ ] Relay hop-limit decrement does not break signature or content authentication at the destination.
- [ ] A relay without the room key forwards the signed ciphertext but does not create a trust entry for an unrelated room.
- [ ] TTL-zero messages are not relayed.
- [ ] Duplicate signed message IDs are neither displayed nor relayed again.

## Trust on first use and fingerprint verification

- [ ] The first valid signed message pins one public key to the sender's stable device ID.
- [ ] The message is labelled first-seen until its fingerprint is compared.
- [ ] Device identities shows the peer device ID, current fingerprint, and First seen state.
- [ ] Compare the fingerprint through a trusted channel independent of the MeshTalk message being verified.
- [ ] Pressing Fingerprint matches changes the identity to Verified.
- [ ] Later messages from the same key are labelled verified sender identity.
- [ ] Restart preserves the pinned key and verified state.
- [ ] Switching rooms preserves the device-ID-to-key trust decision.
- [ ] A room-key holder using a new device ID can still appear as a new first-seen member; no claim is made that TOFU proves real-world identity.

## Identity-key change handling

- [ ] Simulate the same stable device ID presenting a different valid Ed25519 key.
- [ ] The new message is not displayed or persisted in visible room history.
- [ ] The security banner and identity warning report that an identity change is blocked.
- [ ] The old pinned fingerprint remains visible alongside the pending replacement fingerprint.
- [ ] Relay behavior remains independent: the blocked message can still be forwarded as opaque ciphertext.
- [ ] Keep old key clears the pending replacement and does not display the blocked message.
- [ ] A later message signed by the old key remains accepted under its prior trust state.
- [ ] Approve new key replaces the pinned key and releases the most recently blocked message from that sender.
- [ ] An approved replacement returns to First seen and must be compared again before Verified.
- [ ] A stale or already-resolved approval action cannot replace a newer identity decision.
- [ ] Repeated changed-key messages do not silently overwrite the trusted key.

## Message-level end-to-end encryption

- [ ] BLE, Android Nearby, and iOS Multipeer deliver identical encrypted and signed envelope semantics.
- [ ] A device with the matching room code decrypts and displays a valid signed message exactly once.
- [ ] Changing ciphertext or its authentication tag causes rejection and a local security error in diagnostics.
- [ ] A relay device without the room key forwards ciphertext but does not display or persist message content locally.
- [ ] Message rows clearly distinguish local signed, first-seen, verified, unsigned legacy, legacy unencrypted, and unable-to-authenticate states.

## Key storage and recovery

- [ ] Android restart preserves the room key through secure storage.
- [ ] iOS restart preserves the room key through Keychain storage.
- [ ] Android application backup is disabled in the generated manifest.
- [ ] The generated iOS target includes the expected Keychain access-group entitlement.
- [ ] Corrupt secure-room storage produces an initialization error and does not silently create replacement keys.
- [ ] Loss of room-key storage prevents decryption until the valid room code is imported again.
- [ ] Re-importing a saved room code restores access to matching ciphertext but does not recreate another device's signing key.
- [ ] Restoring only the room code causes the reinstalled device signing identity to appear as a changed or new identity to peers, depending on its stable device ID.

## Legacy history and queue migration

- [ ] Existing plaintext history remains readable and is labelled legacy unencrypted history.
- [ ] Existing plaintext history is not falsely labelled encrypted or signed.
- [ ] Protocol-version-1 encrypted history remains locally readable and is labelled unsigned legacy sender.
- [ ] A protocol-version-1 encrypted payload received from the network is rejected because it has no sender signature.
- [ ] A queued plaintext message is converted to active-room signed protocol version 2 before transport delivery.
- [ ] A queued protocol-version-1 ciphertext is decrypted locally and re-encrypted/re-signed as protocol version 2 before transport restoration.
- [ ] Restarting during migration does not duplicate the queued message.
- [ ] A migrated queued message changes to sent only after successful delivery.
- [ ] Encrypted queued messages for another saved room remain stored and are not sent with the active room key.

## BLE mesh

- [ ] Devices discover each other over BLE.
- [ ] A signed encrypted message sends and arrives exactly once in each direction.
- [ ] Large signed encrypted messages cross the negotiated MTU boundary and reassemble correctly.
- [ ] Out-of-order and repeated chunks do not duplicate a message.
- [ ] A third device relays signed ciphertext with hop count decremented.
- [ ] Background and foreground transitions preserve signed encrypted queued messages.

## Android Nearby fallback

- [ ] Test on two physical Android devices with BLE turned off.
- [ ] Version-appropriate Nearby, Bluetooth, Wi-Fi, and legacy location permission prompts appear without storage permission.
- [ ] Denying a required permission shows an actionable settings link.
- [ ] Both devices advertise and discover using the MeshTalk service ID.
- [ ] Exactly one side initiates a discovered connection; duplicate cross-requests do not occur.
- [ ] Malformed, self-identifying, or empty-token endpoints are rejected.
- [ ] The same authentication code appears on both phones before either side accepts.
- [ ] No connected peer or inbound payload appears before both users approve matching codes.
- [ ] Approving matching codes connects the peer and changes the UI to verified Android Nearby.
- [ ] Rejecting, disconnecting, or using a stale verification card does not connect.
- [ ] Signed encrypted messages send exactly once in both directions after verification.
- [ ] The transport comparison code and persistent signing fingerprint are shown as separate security concepts.
- [ ] One failed endpoint does not invalidate successful delivery to another endpoint.
- [ ] When every endpoint fails, signed ciphertext remains queued.
- [ ] Encoded payloads above 32 KiB are rejected without corrupting the session.
- [ ] Turning BLE back on upgrades only after BLE activation succeeds.
- [ ] A failed BLE upgrade leaves the working Android Nearby session active.
- [ ] Android Nearby is not shown or claimed on iOS.

## iOS Multipeer fallback

- [ ] Test a signed development build on two physical iPhones with BLE unavailable.
- [ ] Local Network and Bluetooth prompts use the configured MeshTalk explanations.
- [ ] Denying Local Network permission prevents discovery and leaves a useful diagnostics error.
- [ ] Both phones advertise and browse the `meshtalk-chat` Bonjour service.
- [ ] The deterministic device-ID rule prevents duplicate cross-invitations.
- [ ] Both phones show the same six-digit comparison code for one invitation attempt.
- [ ] The initiating phone does not send its invitation until approval.
- [ ] The receiving phone does not accept the session until approval.
- [ ] Rejection, timeout, or a stale request leaves no connected peer.
- [ ] No peer or byte payload is published before local verification completes.
- [ ] The connected state identifies verified iOS Multipeer rather than Android Nearby.
- [ ] Signed encrypted messages send exactly once in both directions after verification.
- [ ] The Multipeer comparison code and persistent signing fingerprint are shown as separate security concepts.
- [ ] One failed iOS peer does not invalidate successful delivery to another peer.
- [ ] When all iOS peers fail, signed ciphertext remains queued.
- [ ] Encoded payloads above 32 KiB are rejected without corrupting the session.
- [ ] Disconnect/reconnect clears stale invitations and allows new discovery.
- [ ] Force-close/restart preserves room key, signing identity, trust state, ciphertext history, and one queued delivery.
- [ ] Profile rename restarts the previous session before advertising the new name without rotating the signing key.
- [ ] Returning from settings or foreground refreshes the active transport.
- [ ] Restoring BLE upgrades only after BLE activation succeeds.
- [ ] A failed BLE upgrade leaves a working iOS Multipeer session active.
- [ ] The simulator artifact is not treated as a signed physical-device build.

## Transport, encryption, and identity diagnostics

- [ ] The diagnostics button opens from the chat app bar.
- [ ] Session state matches the visible connection card.
- [ ] Encryption is shown as XChaCha20-Poly1305 group E2EE.
- [ ] Sender signatures are shown as Ed25519 protocol v2.
- [ ] Room name and room fingerprint match the room banner.
- [ ] Local identity fingerprint matches Device identities.
- [ ] Pinned-identity and pending-change counts are accurate.
- [ ] Active transport and ID match BLE, Android Nearby, or iOS Multipeer.
- [ ] Bluetooth readiness matches the device radio state.
- [ ] Connected-peer, pending-verification, and queued-message counts are accurate.
- [ ] Payload limit reflects the active transport.
- [ ] Last refresh time changes after pressing Refresh.
- [ ] Native transport failures, signature failures, content-authentication failures, and identity changes appear as the last local error.
- [ ] Diagnostics never display message content, private keys, or room-code material.

## Persistent history and lifecycle

- [ ] Signed encrypted incoming and outgoing history remains after force-close/reopen.
- [ ] Historical identity labels reflect the locally stored trust decision without claiming retroactive real-world verification.
- [ ] A message queued with no peer remains queued after restart.
- [ ] A restored signed message sends once when any active transport gains a peer.
- [ ] Reopening repeatedly does not duplicate history, queue entries, or trust records.
- [ ] Switching BLE to a local-network fallback and back does not duplicate ciphertext history.
- [ ] Upgrading from an earlier build preserves SQLite and labels unsigned legacy rows.
- [ ] Rapid resume and radio callbacks do not start competing transport switches.
- [ ] Foreground resume preserves a working fallback when a higher-priority transport cannot activate.

## Local profile

- [ ] The generated device ID remains stable across restarts.
- [ ] Editing the display name persists across restart.
- [ ] Saving a new display name stops the previous session before re-advertising BLE and platform-fallback names.
- [ ] Display names shorter than 2 or longer than 24 characters are rejected.
- [ ] Editing the display name does not change device ID, room key, signing fingerprint, trust records, or history.

## Security claims and limitations

- [ ] UI and release notes describe shared-room E2EE with persistent device signatures, not Signal-equivalent security.
- [ ] UI explains that anyone with the room code can read content and create messages under a new identity.
- [ ] UI does not claim that first-seen trust proves a person's real-world identity.
- [ ] A verified fingerprint is described as a local user decision based on out-of-band comparison.
- [ ] No claim is made for forward secrecy, post-compromise security, automatic rotation, authenticated group membership, or member revocation.
- [ ] Android Nearby and iOS Multipeer comparison codes are described as connection-attempt verification, separate from persistent signing fingerprints and the room key.
- [ ] Metadata exposure is documented: message/sender/room IDs, timestamp, hop limit, payload size, signing public key, and transport peer information remain visible.
- [ ] Internet relay remains clearly identified as unimplemented.
