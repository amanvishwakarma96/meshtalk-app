# PR #7 validation plan

This milestone is not release-ready until automated checks and physical-device verification both pass.

## Automated gates

- Dart formatting
- Flutter analyzer with fatal infos
- all unit, widget, SQLite, transport, session, relay, and mocked integration tests
- Android project generation and transport permission configuration
- Android release APK compilation
- checksum generation and artifact upload

## Physical Android verification

- compare the same Nearby authentication code on both phones
- confirm no peer or payload is accepted before approval
- verify approval and rejection paths
- verify duplicate and stale requests are suppressed
- send bidirectional messages after verification
- inspect diagnostics across BLE, Nearby, permission denial, and forced error states
- return from app settings and confirm foreground refresh
- verify BLE priority upgrade preserves queue and working fallback safety

Matching authentication codes verify the Nearby connection attempt only. They do not provide message-level end-to-end encryption or prove a person's real-world identity.
