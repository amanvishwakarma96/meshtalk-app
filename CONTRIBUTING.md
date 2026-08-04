# Contributing to MeshTalk

## Branches

`main` must remain releasable. Create focused branches such as:

- `feature/ble-chat-relay`
- `feature/wifi-fallback`
- `fix/mtu-reassembly-timeout`
- `test/transport-upgrade`

Do not push feature work directly to `main`. Merge through a pull request after CI passes.

## Commits

Use Conventional Commits:

- `feat:` user-visible capability
- `fix:` defect correction
- `test:` test-only change
- `docs:` documentation
- `chore:` maintenance or tooling

## Pull requests

A pull request must explain what changed, why it changed, user/developer impact, validation performed, and any security or permission impact. Update `CHANGELOG.md` in the same PR for user-facing behavior.

## Required checks

```bash
flutter pub get
flutter analyze
flutter test --coverage
```

Changes to radio adapters or `core/ble/` also require the physical-device checklist in `docs/manual-test-checklist.md`.

## Definition of done

A feature is complete only when code, tests, documentation, changelog, and applicable manual verification are complete. Do not merge placeholder implementations as completed features.

## Pre-release checklist

- [ ] CI is green on `main`.
- [ ] Manual two-device BLE checklist passed.
- [ ] Permission grant and denial paths tested on a fresh install.
- [ ] Bluetooth-off and mid-session Bluetooth-enable behavior tested.
- [ ] Bluetooth-off/Wi-Fi-on fallback tested.
- [ ] Bluetooth-off/Wi-Fi-off actionable state tested.
- [ ] Transport hot-swap does not lose or duplicate messages.
- [ ] Background/foreground transitions preserve queued messages.
- [ ] README and CHANGELOG match the release.
- [ ] No hidden debug tooling is reachable in release builds.
- [ ] Maintainer explicitly approved store submission.
