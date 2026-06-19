#!/usr/bin/env bash
# Print a combined licence inventory for Loupe + its third-party deps.
#
# Output is a plain-text report with section headers per component, so it
# is suitable for inclusion in a compliance package, an OSS attribution
# screen inside an app, or a legal review.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_section() {
    echo
    echo "==================================================================="
    echo " $1"
    echo "==================================================================="
}

print_section "Loupe (this project)"
sed -n '/^GRANTED PERMISSIONS$/,/^NOT PERMITTED WITHOUT/p' "$REPO_ROOT/LICENSE" | head -n 24

print_section "libwebrtc"
cat <<EOF
Loupe uses libwebrtc (via SwiftPM binaryTarget) for WebRTC peer
connection setup, DTLS-SRTP media encryption, ICE/STUN/TURN, and
codec selection.

libwebrtc is BSD-3-Clause licensed. The exact text shipped with the
resolved WebRTC.xcframework version is the operative licence for that
binary.
  Source: https://webrtc.googlesource.com/src
  Licence: https://chromium.googlesource.com/chromium/src/+/main/LICENSE
EOF

print_section "coturn"
cat <<EOF
The signaling container bundles coturn as the TURN server. coturn is
distributed under the terms listed in the upstream repository:
  Source: https://github.com/coturn/coturn
  Licence: https://github.com/coturn/coturn/blob/master/LICENSE
  Default licence at time of writing: BSD-style with attribution.
EOF

print_section "Fastify"
cat <<EOF
The signaling HTTP/WebSocket server is built on Fastify. Fastify is
MIT-licensed.
  Source: https://github.com/fastify/fastify
  Licence: https://github.com/fastify/fastify/blob/main/LICENSE
EOF

print_section "Apple frameworks"
cat <<EOF
Loupe uses Apple's system frameworks for crypto (CryptoKit, Security),
UI (SwiftUI, UIKit, AppKit), media (ScreenCaptureKit, VideoToolbox,
AVFoundation, CoreMedia), and input injection (CoreGraphics /
CGEventPost). These are governed by Apple's standard SDK terms and
are not separately redistributed.
EOF

print_section "Other"
echo
echo " - Node.js (signaling container runtime): MIT"
echo " - npm packages (resolved in loupe-signaling/package-lock.json):"
echo "     each listed with its own LICENSE in node_modules/<pkg>/LICENSE"
echo " - SwiftPM packages (Package.resolved):"
echo "     each listed with its own LICENCE in <pkg-root>/LICENCE"

echo
echo "For the exact list of resolved npm packages, run:"
echo "  cd loupe-signaling && npm ls --all"
echo
echo "For the exact list of resolved SwiftPM packages, see:"
echo "  loupe-controller-ios/Package.resolved"
echo "  loupe-host-macos/Package.resolved"
echo "  loupe-controller-macos/Package.resolved"
echo "  LoupeControllerMacApp/Package.resolved"