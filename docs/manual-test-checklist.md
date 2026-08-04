# Manual two-device verification

Run this checklist on two physical phones before every release and after changes to `core/ble/` or transport adapters.

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

## Permission and radio states

- [ ] Bluetooth permission denied shows an actionable explanation and settings link.
- [ ] Bluetooth off shows an enable action.
- [ ] Turning Bluetooth on mid-session upgrades transport without losing messages.
- [ ] Bluetooth off and Wi-Fi on activates the local fallback.
- [ ] Bluetooth and Wi-Fi off shows a precise no-transport state.

## Reliability

- [ ] Disconnect/reconnect does not duplicate recently seen messages.
- [ ] Incomplete chunk assemblies expire and release memory.
- [ ] MTU change during a conversation does not corrupt subsequent messages.
- [ ] App restart restores local history and unsent queue.

## Security copy

- [ ] The app clearly states when internet relay is in use.
- [ ] The not-end-to-end-encrypted warning remains visible until E2E ships.
