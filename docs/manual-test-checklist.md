# Manual two-device verification

Run this checklist on physical phones before every release and after changes to BLE, Android Nearby, transport selection, profile, or storage behavior.

## Setup

- [ ] Fresh install on both devices.
- [ ] Record OS version, phone model, Google Play services version, app version, and build number.
- [ ] Grant only the permissions required by each tested path.
- [ ] Confirm the visible security warning remains present.

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
- [ ] The UI labels the active transport as Android Nearby and states that peer identity is not authenticated.
- [ ] A message sends and arrives exactly once in each direction.
- [ ] A message is broadcast to every connected fallback peer.
- [ ] One failed endpoint does not invalidate successful delivery to another endpoint.
- [ ] When every endpoint fails, the message remains queued.
- [ ] Encoded payloads above 32 KiB are rejected without corrupting the session.
- [ ] Disconnecting a peer removes it from the visible peer count.
- [ ] Turning BLE back on upgrades to BLE only after BLE activation succeeds.
- [ ] A failed BLE upgrade leaves the working Android Nearby session active.
- [ ] Android Nearby is not shown or claimed on iOS.

## Persistent history and recovery

- [ ] Incoming and outgoing history remains after force-closing and reopening the app.
- [ ] A message queued with no peer remains labelled queued after restart.
- [ ] A restored queued message sends once when either transport gains a peer.
- [ ] A restored message changes from queued to sent only after successful delivery.
- [ ] Reopening the app repeatedly does not duplicate history or queue entries.
- [ ] Switching BLE to Android Nearby and back does not duplicate history.
- [ ] Upgrading from an earlier build preserves the existing SQLite database.
- [ ] Corrupt or unavailable storage produces a clear initialization failure rather than silent data loss.

## Local profile

- [ ] The generated device ID remains stable across restarts.
- [ ] Editing the display name persists across restart.
- [ ] Saving a new display name stops the previous session before re-advertising the new BLE and Android Nearby names.
- [ ] Display names shorter than 2 or longer than 24 characters are rejected.
- [ ] Editing the display name does not change the device ID or delete history.

## Permission and radio states

- [ ] Bluetooth permission denied shows an actionable explanation and settings link.
- [ ] Android Nearby/local-network permission denied shows an actionable explanation and settings link.
- [ ] Bluetooth off and Android fallback available starts Nearby discovery.
- [ ] Bluetooth off and no fallback shows a precise no-transport state.
- [ ] Turning Bluetooth on mid-session upgrades without losing queued messages.

## Reliability

- [ ] Disconnect and reconnect do not duplicate recently seen messages.
- [ ] Incomplete BLE chunk assemblies expire and release memory.
- [ ] BLE MTU changes do not corrupt subsequent messages.
- [ ] Relay success does not change an incoming message label from received to sent.
- [ ] Repeated Android Nearby start/stop cycles do not leave stale endpoints.

## Security copy

- [ ] Android Nearby is explicitly labelled unverified until authentication-token confirmation is implemented.
- [ ] The app clearly states when an internet relay is in use once implemented.
- [ ] The not-end-to-end-encrypted warning remains visible until E2E ships.
