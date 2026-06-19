# ADR-004 — Native QR scanner on the macOS controller

- Status: Accepted
- Date: 2026-06-19
- Supersedes: the implicit assumption in the original README that Mac controllers
  only support token-paste / token-file pairing.

## Context

`LoupeControllerMacApp` is a MenuBar-resident SwiftUI app. The earlier
implementation deliberately hid the QR scan button on macOS with the message
*“QR-Scan wird auf macOS nicht verwendet”* and pointed users at the token-paste
or token-file flow instead.

That worked, but it created a real friction gap: iPhone and iPad controllers had
a single-tap “Scan QR code” entry point, while Mac users had to find the token
in the LoupeHost console, copy it to the clipboard, then paste it. On a busy
session that is several avoidable manual steps.

macOS 13+ has shipped a stable `AVCaptureSession` + `AVCaptureMetadataOutput`
API for years. Modern Macs (2020+) ship with a FaceTime camera; recent models
add Continuity Camera so an iPhone can act as a wireless webcam. Both show up
to `AVCaptureDevice.default(for: .video)` the same way. The implementation cost
is one file and a SwiftUI `NSViewRepresentable` — well within scope.

## Decision

The macOS controller now ships its own native QR scanner (`MacQRScannerView`)
implemented on top of AppKit + AVFoundation. It mirrors the iOS
`QRScannerViewController` API shape (`MacQRScannerDelegate` is the analogue of
`QRScannerDelegate`) so future shared-Kit refactors stay straightforward.

The pairing view (`MacPairingEntryView`) now offers three equal-footing flows:

1. **Scan QR code** — primary, opens the AVFoundation scanner sheet.
2. **Paste token** — fallback for machines without a working camera.
3. **Open token file** — fallback for headless Macs, scripted flows, and CI.

Token-paste and token-file remain because not every Mac has a camera that the
user is willing to grant Loupe access to, and because the LoupeHost also prints
the raw token on stderr for that exact reason.

## Consequences

Positive:

- Single-step pairing for the iPhone ↔ Mac case when both sides are at the
  same desk — same UX as iOS.
- The macOS app gets a richer onboarding flow (three-step welcome that mirrors
  the iOS WelcomeFlow).
- Symmetry between controllers — every controller can use every pairing flow.

Negative:

- The macOS app now requests camera permission. Privacy manifest is updated
  accordingly (`NSCameraUsageDescription`).
- `AVCaptureSession` must run on the main thread for layout. We already do this
  via `viewDidMoveToWindow` lifecycle hooks so the camera LED turns off when
  the menu bar is collapsed.
- A Mac without any camera (rare, but exists in CI / virtualised environments)
  falls back to the token flows with a clear alert. We deliberately do not
  surface the scanner button in the welcome flow on such machines — the alert
  explains the fallback.

## Alternatives considered

- **Reuse `QRScannerViewController` from `LoupeControllerKit`.** Rejected:
  that class is `UIViewController` + `import UIKit`, which does not link on
  pure macOS. Mac Catalyst would work but forces a single shared build target,
  which we are not ready to commit to.
- **Use a JavaScript-based QR decoder in WebKit.** Rejected: heavyweight, no
  camera access without extra entitlements, and the user expects the system
  camera UI, not a web view.
- **Keep token-only on macOS.** Rejected because the friction delta vs. iOS
  was noticeable in manual testing and the engineering cost to fix it is small.
