# Loupe Changelog

## v0.3-ui-diagnostics-plus

Additive development on top of the build-green UI/Diagnostics baseline.

### Added

- Controller runtime event timeline exposed through `ControllerViewModel.recentEvents`.
- Controller Diagnostics export now includes recent runtime events.
- Host runtime logs now include local SDP generation, local/remote ICE counters and input event counters.
- `scripts/loupe-doctor.sh` for server, TURN, TypeScript and project structure checks.
- `scripts/run-xcode-builds.sh` for reproducible macOS/iOS builds.
- `scripts/create-release-zip.sh` for clean project packaging.
- `scripts/open-host-qr.sh` for opening the active pairing QR.
- `docs/openclaw-next-prompt.md` with the next exact OpenClaw workflow.
- `docs/iphone-test-acceptance.md` with concrete pass/fail criteria.
- `docs/product-roadmap.md` with the next product phases.

### Preserved

- Signaling protocol unchanged.
- TURN/STUN flow unchanged.
- WebRTC offer/answer lifecycle unchanged.
- Pairing token payload unchanged.
- Public endpoint unchanged: `wss://loupe.ddns.net/ws`.

### Verified in this environment

- Signaling `npm run typecheck`: passed.
- Signaling `npm run build`: passed.
- Signaling `npm run test:smoke`: passed.

Swift/Xcode targets still require local Xcode/macOS SDK validation.
