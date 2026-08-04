# Manual two-device verification

Run this checklist on two physical phones before every release and after changes to BLE, transport, profile, or storage behavior.

## Setup

- [ ] Fresh install on both devices.
- [ ] Record OS version, phone model, app version, and build number.
- [ ] Grant only the permissions required by each tested path.

## BLE mesh

- [ ] Devices discover each other over BLE.
- [ ] A message sends and arrives exactly once in each direction.
- [ ] Large messages cross the negotiated MTU boundary and reassemble correctly.
- [ ] Out-of-order and repeated chunks do not duplicate a message.
- [ ] A third device relays a message with hop count decremented.
- [ ] TTL zero messages are not relayed.
- [ ] Background and foreground transitions preserve queued messages.

## Persistent history and recovery

- [ ] Incoming and outgoing history remains after force-closing and reopening the app.
- [ ] A message queued with no peer remains labelled queued after restart.
- [ ] A restored queued message sends once when a peer reconnects.
- [ ] A restored message changes from queued to sent only after successful delivery.
- [ ] Reopening the app repeatedly does not duplicate history or queue entries.
- [ ] Upgrading from an earlier build preserves the existing SQLite database.
- [ ] Corrupt or unavailable storage produces a clear initialization failure rather than silent data loss.

## Local profile

- [ ] The generated device ID remains stable across restarts.
- [ ] Editing the display name persists across restart.
- [ ] Saving a new display name restarts BLE discovery and advertises the new name.
- [ ] Display names shorter than 2 or longer than 24 characters are rejected.
- [ ] Editing the display name does not change the device ID or delete history.

## Permission and radio states

- [ ] Bluetooth permission denied shows an actionable explanation and settings link.
- [ ] Bluetooth off shows an enable action.
- [ ] Turning Bluetooth on mid-session upgrades transport without losing messages.
- [ ] Bluetooth off and Wi-Fi on activates the local fallback when implemented.
- [ ] Bluetooth and Wi-Fi off shows a precise no-transport state.

## Reliability

- [ ] Disconnect and reconnect do not duplicate recently seen messages.
- [ ] Incomplete chunk assemblies expire and release memory.
- [ ] MTU change during a conversation does not corrupt subsequent messages.
- [ ] Relay success does not change an incoming message label from received to sent.

## Security copy

- [ ] The app clearly states when internet relay is in use.
- [ ] The not-end-to-end-encrypted warning remains visible until E2E ships.
