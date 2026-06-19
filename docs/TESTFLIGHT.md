# TestFlight & App Store distribution

End-to-end procedure for cutting a TestFlight build of the iOS controller
and (later) shipping it to the App Store. Last validated against Xcode 27.0
(Beta) on 2026-06-19, with the iOS controller at version `1.0.0`.

## What TestFlight needs from the iOS app

| Requirement | Where we are |
|---|---|
| `NSCameraUsageDescription` | Set in pbxproj (`Kamera wird benötigt, um den Loupe-Pairing-QR-Code zu scannen.`) |
| `NSLocalNetworkUsageDescription` | Set in pbxproj |
| `PrivacyInfo.xcprivacy` (iOS 17+ mandate) | `apps/LoupeControllerApp/LoupeControllerApp/PrivacyInfo.xcprivacy` — declares `CA92.1`, `C617.1`, `35F9.1` |
| `UILaunchScreen` (or storyboard) | Auto-generated via `INFOPLIST_KEY_UILaunchScreen_Generation = YES` |
| `MARKETING_VERSION` (3 segments) | `1.0.0` |
| `CURRENT_PROJECT_VERSION` (build number) | `1` |
| App icon set, all required sizes | Done in the brand track (commit `72394c4`) |
| Code signing identity | `Apple Development`, automatic, Team `355NB9T8RJ` |
| `TARGETED_DEVICE_FAMILY` | `1,2` (iPhone + iPad) — **no Mac Catalyst** |

The macOS controller is **not** TestFlight-eligible — Apple has never shipped
TestFlight for macOS. The mac controller ships either via the Mac App Store
(after signing + notarisation) or as a Developer-ID build that users
download from `loupe.ddns.net`. See `docs/ADR-004-mac-camera-pairing.md`.

## One-time App Store Connect setup

The very first time you push a build, a human needs to do this. After that
it is repeatable.

1. Open <https://appstoreconnect.apple.com> in a browser.
2. Sign in with the Apple ID that owns the team (`bigbadboy1010`).
3. Confirm the Team Agent has accepted the latest Apple Developer Program
   agreement (otherwise every step below errors with "you do not have
   permission").
4. **My Apps** → **+** → **New App**.
5. Fill in:
   - Platforms: **iOS**
   - Name: **Loupe**
   - Primary Language: **English** (or whichever you prefer)
   - Bundle ID: **`org.francois.loupe`** (must match the pbxproj)
   - SKU: `loupe-controller-v1` (anything opaque is fine, used for your
     own bookkeeping)
   - User Access: **Full Access** for internal testing; **Limited Access**
     if you want external testers to read a non-disclosure summary first
6. After creating the app, open the **TestFlight** tab. Create at least
   one **Internal Testing** group (you, the account holder). External
   testing groups can be added later.

You can close App Store Connect at this point — everything else is `xcodebuild`.

## Build the archive

```bash
cd ~/Desktop/Loupe/apps/LoupeControllerApp
xcodebuild \
    -project LoupeControllerApp.xcodeproj \
    -scheme LoupeControllerApp \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -archivePath /tmp/LoupeControllerApp.xcarchive \
    archive
```

Notes:

- Always `Release`. Debug archives can be uploaded to TestFlight, but
  App Store review rejects debug-only builds.
- `generic/platform=iOS` is the canonical "any iOS device" destination.
  Specific destinations (your iPhone) work too but slow the archive.
- If `xcodebuild` complains about code signing, run the same command
  with `-allowProvisioningUpdates` once to refresh the profile, then
  re-run without it.

## Export the archive for upload

For TestFlight, you do **not** need an export-options.plist if you upload
directly with `xcrun altool` or the modern `xcrun notarytool` successor.
Two clean options:

### Option A — Xcode Organizer (manual, useful while iterating)

1. Open the archive in Xcode: **Window → Organizer → Archives**
2. Pick the archive → **Distribute App** → **TestFlight & App Store** →
   **Upload**
3. Follow the wizard. Apple will ask for an **App Store Connect API key**
   or a Team Agent password the first time.

### Option B — `xcrun altool` (scriptable)

```bash
xcrun altool --upload-app \
    --type ios \
    --file /tmp/LoupeControllerApp.xcarchive \
    --bundle-id org.francois.loupe \
    --bundle-version 1.0.0 \
    --bundle-short-version-string 1.0.0 \
    --username "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD"
```

`$APP_SPECIFIC_PASSWORD` is an app-specific password generated at
<https://appleid.apple.com/account/manage> → App-Specific Passwords. Do
**not** reuse your Apple ID password.

For App Store Connect API keys (preferred, more scriptable), generate one
at <https://appstoreconnect.apple.com/access/integrations/api>, then use
`xcrun altool --apiKey ... --apiIssuer ...`.

## After upload

1. In App Store Connect → your app → **TestFlight** tab, the build shows
   up with a yellow "Missing Compliance" badge the first time.
2. Click the build → answer the export-compliance prompts. For Loupe
   the answer is:
   - **Does your app use encryption?** Yes.
   - **Is your app exempt from EU encryption reporting (only uses
     HTTPS, standard cryptographic APIs)?** Yes (we use DTLS-SRTP via
     libwebrtc + standard WebSockets; no custom crypto).
   That lets you skip the annual CCATS submission.
3. Apple runs a ~24-48h automated review for the first TestFlight
   build. After that, new builds from the same version line are
   approved in minutes.
4. Add internal testers by Apple ID email. They get a TestFlight
   invitation email and install the app via the TestFlight app.

## What can go wrong

- **"Unable to resolve module dependency: 'UIKit'" in Xcode editor.**
  This is a known Xcode 27 Beta editor false-positive. The CLI build
  succeeds. The pbxproj already references `UIKit.framework`,
  `SwiftUI.framework`, and `UniformTypeIdentifiers.framework`
  explicitly. To silence it: **Product → Clean Build Folder** then
  close + reopen Xcode.
- **"Provisioning profile '…' doesn't include signing certificate
  'Apple Development'."** Run the archive command once with
  `-allowProvisioningUpdates`.
- **"ITMS-90034: Missing or invalid signature."** Usually means the
  archive was signed with the wrong identity. Run
  `xcodebuild -showBuildSettings -target LoupeControllerApp | grep
  CODE_SIGN_IDENTITY` to confirm it is `Apple Development`, not
  `iPhone Developer`.
- **"ITMS-90328: Missing Info.plist key NSCameraUsageDescription."**
  Should never happen now (we set it in pbxproj), but if you ever
  fork the project, remember to keep that line.

## See also

- `docs/architecture.md` — overview of the controller/host split
- `docs/ADR-002-libwebrtc.md` — why we embed `WebRTC.xcframework`
  and which export-compliance consequences that has
- `docs/iphone-test-acceptance.md` — what a tester is supposed to
  verify once TestFlight has shipped the build
