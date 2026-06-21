# TestFlight & App Store Connect listing copy

> Single source of truth for the user-facing strings shown on
> [TestFlight](https://testflight.apple.com/join/wsJeRw1M) and
> (later) the App Store listing for `LoupeControllerApp`.
>
> Every change to App Name, Subtitle, Description, What's New,
> or Marketing URL must be applied here **and** in App Store Connect
> in the same change. Drift between the two is a public-beta trust
> regression.

**Bundle ID:** `org.francois.loupe.controller`
**App Store Connect app name:** `LoupeControllerApp`
**Primary locale:** `en-US`
**Last updated:** 2026-06-21

---

## App Name (max 30 chars)

```
LoupeControllerApp
```

> 19 characters. Do NOT rename to "Loupe" — TestFlight and the
> App Store treat the bundle as a separate app from any future
> "Loupe Host" listing, and reviewers look up the name in their
> crash reports.

## Subtitle (max 30 chars)

```
Remote desktop for your Mac
```

> 27 characters. Avoid dashes, slashes, or punctuation — App Store
> Connect strips them silently in some locales.

## Promotional Text (max 170 chars; can be updated without a new build)

```
Apple-native remote desktop. Pair your Mac and iPhone with a QR code,
control it with touch and trackpad, end-to-end encrypted.
```

## Description

```
LoupeControllerApp is the Apple-native remote desktop controller for
Loupe. Pair your iPhone or iPad with your Mac over a QR code and use
touch, trackpad, scroll, and keyboard to control it — with sub-50 ms
glass-to-glass latency and end-to-end encryption between your devices.

Loupe uses WebRTC with DTLS-SRTP for the media and input channels.
The signaling server only relays opaque SDP and ICE; it never sees
your screen, keystrokes, or clipboard. Pairing uses Trust On First
Use with public-key pinning — the first scan locks the controller to
the host, and any future MITM attempt is rejected with a visible
fingerprint mismatch.

• Mac → iPhone is view-only. Apple does not allow third-party apps
  to inject input on iOS.
• Loupe is source-available. You can self-host the signaling and
  TURN relay on a $5/month VPS and point the apps at it.
• No account. No media cloud. No analytics. No tracking cookies.
  See https://theloupe.team/privacy.html for the full data policy.

Status, current build, and known issues are listed on
https://theloupe.team/status.html. To report a vulnerability, email
security@theloupe.team (PGP key in SECURITY.md).
```

## Keywords (max 100 chars, comma-separated)

```
remote desktop,mac control,apple,webrtc,e2e,developer,free,no account,pairing
```

## Support URL

```
https://theloupe.team/
```

## Marketing URL

```
https://theloupe.team/
```

## Privacy Policy URL

```
https://theloupe.team/privacy.html
```

## What's New (this build)

> Keep tight — App Store Connect caps this at 4000 chars but the
> visible area on TestFlight is ~150 chars before "more".

```
First public beta of the iOS / iPadOS controller. Pair with a Mac
running LoupeHost v0.2.0+ via QR code, control with touch and
trackpad, end-to-end encrypted. See https://theloupe.team/status.html
for current build, known issues, and roadmap.
```

## What's New (subsequent builds)

Use the format:

```
<VERSION> — <short feature sentence>. See https://theloupe.team/CHANGELOG.md
for the full change list.
```

---

## Common reviewer traps to avoid

- **Do not** use "Iphone" (capital I only). Use "iPhone". TestFlight
  displays the raw subtitle and description verbatim in most locales,
  and Apple has historically flagged the typo.
- **Do not** describe Loupe as "the fastest remote desktop" or any
  superlative without a citation. App Store Review Guideline 4.3
  ("spam and misleading metadata") is the usual rejection reason.
- **Do not** promise features that are still on the roadmap. The
  status page is the canonical "what works today" answer; if a
  feature is listed there as `Planned`, it must not appear in the
  TestFlight description as a current capability.
- **Do not** add analytics SDKs. The privacy posture is
  "no analytics, no tracking, no third-party scripts". Adding
  Firebase, Sentry, or any SDK invalidates the privacy claim on
  the marketing site.

## Drift detection

After every release, run a quick manual check from the TestFlight
iOS app (or `xcrun altool --validate-app`):

1. Open the public beta page and read the description out loud.
2. Compare every sentence against this file.
3. If anything diverges, edit this file **and** the App Store
   Connect listing in the same change.
