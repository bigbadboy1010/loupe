# Contributing to Loupe

Thanks for being here. Loupe is a small project and most of the value comes from people using it, reporting how it broke, and sending small, focused PRs.

## What we need most right now

- **Real-device testing reports.** Boot it on a Mac and an iPhone. What works, what doesn't, what surprised you. Open an issue with the device + macOS/iOS version + logs from `~/Library/Logs/com.miggu69.loupe/` if you can.
- **Bug reports with a minimal reproduction.** Bonus points if you can narrow it to one input gesture, one display setup, or one network condition.
- **Documentation that says what you'd want to read.** If the README confused you, open a PR that fixes the sentence that confused you.

We are not currently looking for big architectural changes. The protocol is at `v3.6-stable` and we want to keep it stable while we ship the public beta.

## Code style

### Swift (`loupe-host-macos`, `loupe-controller-ios`)
- Swift 5.9+ toolchain.
- Public types and functions get doc comments. Internal helpers don't need them.
- Run `swift build` and `swift test` before opening a PR.
- Prefer value types. Classes only when you need lifetime control.

### TypeScript (`loupe-signaling`)
- Node ≥ 20, ESM modules.
- `npm run typecheck && npm test` must pass. That's the whole CI gate.
- Prefer small, focused modules under `src/`. The Fastify router stays thin; logic goes into the modules it calls.
- Zod for any external input boundary. No `any` outside generated code.

## Pull request flow

1. Branch off `main`.
2. Make your change. Commit messages should explain the *why*, not just the *what*.
3. Run the relevant build + tests locally.
4. Open the PR against `main`. Include:
   - What changed (one paragraph).
   - How you tested it.
   - Screenshots / logs if the change is user-visible.
5. If you change the protocol, update `docs/webrtc-negotiation.md` and bump the protocol section of `CHANGELOG.md`.

## Reporting security issues

**Please don't file a public issue.** Email `security@theloupe.team`. See [SECURITY.md](SECURITY.md) for the full policy, including PGP key and our response timeline.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). TL;DR: be kind, assume good faith, focus on the work.

## License

By contributing, you agree that your contributions will be licensed under the project's license (see [LICENSE](LICENSE)).
