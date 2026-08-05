# Manual two-device verification

Run this checklist on physical phones before every release and after changes to BLE, Android Nearby, iOS Multipeer, transport selection, verification, profile, diagnostics, lifecycle, or storage behavior.

## Setup

- [ ] Fresh install on both devices.
- [ ] Record OS version, phone model, Google Play services version where applicable, app version, and build number.
- [ ] Grant only the permissions required by each tested path.
- [ ] Confirm the visible not-end-to-end-encrypted warning remains present.

## BLE mesh

- [ ] Devices discover each other over BLE.
- [ ] A message sends and arrives exactly once in each direction.
- [ ] Large messages cross the negotiated MTU boundary and reassemble correctly.
- [ ] Out-of-order and repeated chunks do not duplicate a message.
- [ ] A third device relays a message with hop count decremented.
- [ ] TTL zero messages are not relayed.
- [ ] Background and foreground transitions preserve queued messages.

## Android Nearby fallback

- [ ] Test on two physical Android devices with BLE turned off.
- [ ] Version-appropriate Nearby, Bluetooth, Wi-Fi, and legacy location permission prompts appear without storage permission.
- [ ] Denying a required permission shows an actionable settings link.
- [ ] Both devices advertise and discover using the MeshTalk service ID.
- [ ] Exactly one side initiates a discovered connection; duplicate cross-requests do not occur.
- [ ] Malformed or non-MeshTalk endpoint names are not accepted.
- [ ] Self-identifying endpoints are ignored.
- [ ] Empty authentication tokens are rejected.
- [ ] The same authentication code appears on both phones before either side accepts.
- [ ] No connected peer or inbound payload appears before both users approve matching codes.
- [ ] Approving matching codes connects the peer and changes the UI to verified Android Nearby.
- [ ] Rejecting on either phone removes the pending request and does not connect.
- [ ] Repeated connection callbacks do not create duplicate verification cards.
- [ ] A stale verification card cannot accept a disconnected endpoint.
- [ ] A message sends and arrives exactly once in each direction after verification.
- [ ] A message is broadcast to every connected verified fallback peer.
- [ ] One failed endpoint does not invalidate successful delivery to another endpoint.
- [ ] When every endpoint fails, the message remains queued.
- [ ] Encoded payloads above 32 KiB are rejected without corrupting the session.
- [ ] Disconnecting a peer removes it from the visible peer count.
- [ ] Turning BLE back on upgrades to BLE only after BLE activation succeeds.
- [ ] A failed BLE upgrade leaves the working Android Nearby session active.
- [ ] Android Nearby is not shown or claimed on iOS.

## iOS Multipeer fallback

- [ ] Test a signed development build on two physical iPhones with BLE unavailable.
- [ ] The Local Network and Bluetooth usage prompts use the configured MeshTalk explanations.
- [ ] Denying Local Network permission prevents discovery and leaves a useful error in diagnostics.
- [ ] Both phones advertise and browse the `meshtalk-chat` Bonjour service.
- [ ] The deterministic device-ID rule prevents duplicate cross-invitations.
- [ ] Both phones show the same six-digit comparison code for one invitation attempt.
- [ ] The initiating phone does not send its invitation until its user approves.
- [ ] The receiving phone does not accept the session until its user approves.
- [ ] Rejecting or allowing the verification timer to expire leaves no connected peer.
- [ ] A stale verification request cannot approve a vanished invitation.
- [ ] No peer or byte payload is published before local verification completes.
- [ ] The connected state identifies verified iOS Multipeer Connectivity rather than Android Nearby.
- [ ] Messages send exactly once in both directions after verification.
- [ ] Reliable byte delivery works across multiple verified peers.
- [ ] One failed iOS peer does not invalidate successful delivery to another peer.
- [ ] When all iOS peers fail, the message remains queued.
- [ ] Encoded payloads above 32 KiB are rejected without corrupting the session.
- [ ] Disconnect/reconnect clears stale invitations and allows new discovery.
- [ ] Force-close/restart preserves history and restores one queued delivery.
- [ ] Profile rename restarts the previous session before advertising the new name.
- [ ] Returning from settings or foreground refreshes the active transport.
- [ ] Restoring BLE upgrades only after BLE activation succeeds.
- [ ] A failed BLE upgrade leaves a working iOS Multipeer session active.
- [ ] The simulator artifact is not treated as a signed physical-device build.

## Transport diagnostics

- [ ] The diagnostics button opens from the chat app bar.
- [ ] Session state matches the visible connection card.
- [ ] Active transport and transport ID match BLE, Android Nearby, or iOS Multipeer.
- [ ] Bluetooth readiness matches the device radio state.
- [ ] Connected-peer, pending-verification, and queued-message counts are accurate.
- [ ] Payload limit reflects the active transport.
- [ ] Last refresh time changes after pressing Refresh.
- [ ] A forced native transport failure appears as the last transport error.
- [ ] Diagnostics contain no message payload, authentication token, or personal data beyond the local transport state.

## Persistent history and recovery

- [ ] Incoming and outgoing history remains after force-closing and reopening the app.
- [ ] A message queued with no peer remains labelled queued after restart.
- [ ] A restored queued message sends once when any active transport gains a peer.
- [ ] A restored message changes from queued to sent only after successful delivery.
- [ ] Reopening the app repeatedly does not duplicate history or queue entries.
- [ ] Switching BLE to a platform local-network fallback and back does not duplicate history.
- [ ] Upgrading from an earlier build preserves the existing SQLite database.
- [ ] Corrupt or unavailable storage produces a clear initialization failure rather than silent data loss.

## Local profile

- [ ] The generated device ID remains stable across restarts.
- [ ] Editing the display name persists across restart.
- [ ] Saving a new display name stops the previous session before re-advertising the new BLE and platform fallback names.
- [ ] Display names shorter than 2 or longer than 24 characters are rejected.
- [ ] Editing the display name does not change the device ID or delete history.

## Permission, lifecycle, and radio states

- [ ] Bluetooth permission denied shows an actionable explanation and settings link.
- [ ] Platform local-network permission denial shows an actionable explanation or diagnostics error and settings recovery path.
- [ ] Bluetooth off and a platform fallback available starts local discovery.
- [ ] Bluetooth off and no fallback shows a precise no-transport state.
- [ ] Turning Bluetooth on mid-session upgrades without losing queued messages.
- [ ] Returning from app settings refreshes permissions and transport availability.
- [ ] Rapid resume and radio callbacks do not start competing transport switches.
- [ ] Foreground resume preserves a working fallback when a higher-priority transport still cannot activate.

## Reliability

- [ ] Disconnect and reconnect do not duplicate recently seen messages.
- [ ] Incomplete BLE chunk assemblies expire and release memory.
- [ ] BLE MTU changes do not corrupt subsequent messages.
- [ ] Relay success does not change an incoming message label from received to sent.
- [ ] Repeated Android Nearby start/stop cycles do not leave stale endpoints or verification requests.
- [ ] Repeated iOS Multipeer start/stop cycles do not leave stale sessions, invitations, or verification requests.

## Security copy

- [ ] Android Nearby and iOS Multipeer explain that users must compare the same authentication code on both phones.
- [ ] iOS Multipeer uses required `MCSession` link encryption.
- [ ] A verified platform connection is not described as message-level end-to-end encryption or verified real-world identity.
- [ ] The app clearly states when an internet relay is in use once implemented.
- [ ] The not-end-to-end-encrypted warning remains visible until E2E ships.
