# Manual two-device verification

Run this checklist on physical phones before every release and after changes to encryption, secure storage, room codes, BLE, Android Nearby, iOS Multipeer, transport selection, verification, profile, diagnostics, lifecycle, or storage behavior.

## Setup

- [ ] Fresh install on both devices.
- [ ] Record OS version, phone model, Google Play services version where applicable, app version, and build number.
- [ ] Grant only the permissions required by each tested path.
- [ ] Confirm the active encrypted-room name, key fingerprint, and end-to-end encrypted banner are visible.
- [ ] Confirm diagnostics do not expose the room code, full key, plaintext, ciphertext, or peer authentication token.

## Encrypted room creation and sharing

- [ ] The first launch creates one encrypted room and keeps the same room ID, key fingerprint, and history after restart.
- [ ] Creating a room generates a different room ID, key fingerprint, and room code.
- [ ] Room names shorter than 2 or longer than 32 characters are rejected.
- [ ] Copying the room code places one complete `MT1` code on the clipboard.
- [ ] Modifying any room-code character causes checksum or format rejection.
- [ ] Pasting the valid code on a second device imports the same room ID, name, fingerprint, and key.
- [ ] Re-importing the same room does not duplicate its secure-storage entry.
- [ ] A room ID already stored with different key material is rejected.
- [ ] The room dialog warns that anyone with the code can read and send messages.
- [ ] Clipboard history is cleared manually after sharing on keyboards or operating systems that retain copied secrets.

## Message-level end-to-end encryption

- [ ] A new outgoing message is shown as end-to-end encrypted.
- [ ] The SQLite envelope payload does not contain the visible plaintext.
- [ ] BLE, Android Nearby, and iOS Multipeer deliver the same encrypted envelope semantics.
- [ ] A device with the matching room code decrypts and displays the message exactly once.
- [ ] A device with another room key does not display or persist the ciphertext as a received message.
- [ ] Changing ciphertext or its authentication tag causes rejection and a local encryption error in diagnostics.
- [ ] Changing message ID, sender ID, room ID, or timestamp causes authentication failure.
- [ ] Relay hop-limit decrement does not break authentication at the destination.
- [ ] A relay device without the room key forwards ciphertext but does not display or persist the message locally.
- [ ] TTL-zero encrypted messages are not relayed.
- [ ] Duplicate encrypted message IDs are neither displayed nor relayed again.
- [ ] Message rows clearly distinguish encrypted, legacy unencrypted, and unable-to-authenticate states.

## Key storage and recovery

- [ ] Android restart preserves the room key through secure storage.
- [ ] iOS restart preserves the room key through Keychain storage.
- [ ] Android application backup is disabled in the generated manifest.
- [ ] The generated iOS target includes the expected Keychain access-group entitlement.
- [ ] Corrupt secure-room storage produces an initialization error and does not silently create replacement keys.
- [ ] Loss of secure storage prevents decryption until the valid room code is imported again.
- [ ] Re-importing a saved room code restores access to matching ciphertext.
- [ ] Application uninstall/reinstall behavior is recorded for each tested OS version because platform secure-storage retention differs.

## Legacy history and queue migration

- [ ] Existing plaintext history remains readable and is labelled legacy unencrypted history.
- [ ] Existing plaintext history is not falsely labelled encrypted.
- [ ] A legacy queued plaintext message is converted to active-room ciphertext before transport delivery.
- [ ] Restarting during migration does not duplicate the queued message.
- [ ] A migrated queued message changes to sent only after successful delivery.
- [ ] Encrypted queued messages for another saved room remain stored and are not sent with the active room key.

## BLE mesh

- [ ] Devices discover each other over BLE.
- [ ] An encrypted message sends and arrives exactly once in each direction.
- [ ] Large encrypted messages cross the negotiated MTU boundary and reassemble correctly.
- [ ] Out-of-order and repeated chunks do not duplicate a message.
- [ ] A third device relays ciphertext with hop count decremented.
- [ ] Background and foreground transitions preserve encrypted queued messages.

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
- [ ] Encrypted messages send exactly once in both directions after verification.
- [ ] One failed endpoint does not invalidate successful delivery to another endpoint.
- [ ] When every endpoint fails, ciphertext remains queued.
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
- [ ] Encrypted messages send exactly once in both directions after verification.
- [ ] One failed iOS peer does not invalidate successful delivery to another peer.
- [ ] When all iOS peers fail, ciphertext remains queued.
- [ ] Encoded payloads above 32 KiB are rejected without corrupting the session.
- [ ] Disconnect/reconnect clears stale invitations and allows new discovery.
- [ ] Force-close/restart preserves the room key, ciphertext history, and one queued delivery.
- [ ] Profile rename restarts the previous session before advertising the new name.
- [ ] Returning from settings or foreground refreshes the active transport.
- [ ] Restoring BLE upgrades only after BLE activation succeeds.
- [ ] A failed BLE upgrade leaves a working iOS Multipeer session active.
- [ ] The simulator artifact is not treated as a signed physical-device build.

## Transport and encryption diagnostics

- [ ] The diagnostics button opens from the chat app bar.
- [ ] Session state matches the visible connection card.
- [ ] Encryption is shown as XChaCha20-Poly1305 group E2EE.
- [ ] Room name and short key fingerprint match the room banner.
- [ ] Active transport and ID match BLE, Android Nearby, or iOS Multipeer.
- [ ] Bluetooth readiness matches the device radio state.
- [ ] Connected-peer, pending-verification, and queued-message counts are accurate.
- [ ] Payload limit reflects the active transport.
- [ ] Last refresh time changes after pressing Refresh.
- [ ] Forced native transport failures and ciphertext authentication failures appear as the last local error.
- [ ] Diagnostics never display message content or room-code material.

## Persistent history and lifecycle

- [ ] Encrypted incoming and outgoing history remains after force-close/reopen.
- [ ] A message queued with no peer remains queued after restart.
- [ ] A restored encrypted message sends once when any active transport gains a peer.
- [ ] Reopening repeatedly does not duplicate history or queue entries.
- [ ] Switching BLE to a local-network fallback and back does not duplicate ciphertext history.
- [ ] Upgrading from an earlier build preserves the existing SQLite database and labels legacy rows.
- [ ] Rapid resume and radio callbacks do not start competing transport switches.
- [ ] Foreground resume preserves a working fallback when a higher-priority transport cannot activate.

## Local profile

- [ ] The generated device ID remains stable across restarts.
- [ ] Editing the display name persists across restart.
- [ ] Saving a new display name stops the previous session before re-advertising BLE and platform-fallback names.
- [ ] Display names shorter than 2 or longer than 24 characters are rejected.
- [ ] Editing the display name does not change the device ID, room key, fingerprint, or history.

## Security claims and limitations

- [ ] UI and release notes describe shared-key group E2EE, not Signal-equivalent security.
- [ ] UI explains that anyone with the room code can read and create messages.
- [ ] No claim is made for forward secrecy, post-compromise security, automatic rotation, member revocation, or real-world identity verification.
- [ ] Android Nearby and iOS Multipeer comparison codes are described as connection-attempt verification, separate from the encrypted-room key.
- [ ] Metadata exposure is documented: message/sender/room IDs, timestamp, hop limit, payload size, and transport peer information remain visible.
- [ ] Internet relay remains clearly identified as unimplemented.
