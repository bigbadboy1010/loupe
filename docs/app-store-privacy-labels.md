# Loupe App Store Privacy Labels — Sprint 19 (2026-06-23)

## Scope

This document captures the data we **do** and **do not** collect,
in the format App Store Connect asks for when you submit the
LoupeControllerApp for the iOS App Store. The Privacy nutrition
labels are a **self-declared** table that Apple shows under the
"App Privacy" section of the App Store listing.

The Loupe Host (macOS) is **not** distributed via the Mac App Store
yet (it ships as a Developer-ID-notarised `.dmg` from
`github.com/bigbadboy1010/loupe/releases`), so this document is
about the iOS controller only. The Mac host's privacy posture is
described in `docs/threat-model.md` and `loupe-signaling/site/privacy.html`.

## Data we do NOT collect

The following data categories are **never** collected, stored, or
transmitted by Loupe:

- **Contact Info** (name, email, phone, physical address)
- **Financial Info** (payment, credit, bank)
- **Health & Fitness**
- **Sensitive Info**
- **Contacts** (address-book)
- **User Content** (photos, videos, audio, gameplay, customer support)
- **Browsing History**
- **Search History**
- **Identifiers** (user ID, device ID, advertising ID)
- **Usage Data** (product interaction, advertising data, other
  usage data)
- **Diagnostics** (crash data, performance data, other diagnostic
  data) — see Sprint 23 for the optional opt-in diagnostic
  pipeline; the default in the iOS app is **off**
- **Purchases**
- **Location**
- **Contacts**
- **Body**
- **Environment** (AR, screen recording)
- **Voice** (speech recognition, sound)

## Data we DO collect

**None.** The Loupe iOS controller has zero data-collection
behaviours. The only network traffic the app generates is the
WebRTC handshake with the user's own Mac host (via the
Loupe signaling relay) and the WebRTC media stream. The
signaling relay is the one the user paired with (public at
`wss://theloupe.team` or a self-hosted instance).

## Required-Reason API Usage

iOS 17+ requires apps to declare any use of the following
APIs in the Privacy Manifest (`PrivacyInfo.xcprivacy`):

| API Category | Reason | Where we use it |
|---|---|---|
| `UserDefaults` | CA92.1 — access info from same app, per documentation | Persist the iOS app's preferences (last-used host, display picker) |
| `FileTimestamp` | C617.1 — display to user, per documentation | Show file-modification time in the "Paired Hosts" sheet |
| `SystemBootTime` | 35F9.1 — measure time elapsed, per documentation | Latency diagnostic (touch-to-pixel end-to-end) |
| `DiskSpace` | 85F4.1 — write or modify file, per documentation | Reserve enough disk for the data-channel's send buffer |

## Tracking

**`NSPrivacyTracking = false`.** Loupe does not track the user
across other companies' apps or websites. The app has no
third-party SDKs, no analytics, no advertising, and no
fingerprinting.

**`NSPrivacyTrackingDomains = []`.** Empty because we don't
track.

## User-Identifiable Data

The WebRTC peer-id is a 32-byte Curve25519 signing public key
generated on first launch and stored in the iOS Keychain. It is
**never** sent to any party other than the user's paired host.
It is not a "user ID" in the App-Store-Connect sense; it does
not identify a human, it identifies the keypair on this iOS
device.

## Privacy URL

The Privacy URL exposed in App Store Connect is:

```
https://theloupe.team/privacy.html
```

This page is the canonical user-facing privacy notice; the
in-app privacy notice is a short summary that links to it.

## How to update this document

1. Add a new data category **only** if the Loupe iOS app
   starts using a system API that Apple has marked as a
   "data type" (e.g. photo library, calendar, contacts).
2. Update `PrivacyInfo.xcprivacy` to declare the new
   accessed-API type and reason code.
3. Update the table in this document to keep the App-Store
   listing in sync.
4. Update `loupe-signaling/site/privacy.html` with the
   user-facing wording.
5. Cut a new host-binary release + iOS TestFlight build
   that includes the updated `PrivacyInfo.xcprivacy`.
6. Re-submit the iOS app to App Store Connect with the new
   privacy labels.

## See also

- `apps/LoupeControllerApp/LoupeControllerApp/PrivacyInfo.xcprivacy`
- `loupe-signaling/site/privacy.html`
- `docs/threat-model.md`
- `loupe-controller-ios/.../Sentinel/` (on-device Privacy
  Sentinel — Sprint 16)
