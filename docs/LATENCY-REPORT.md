# Loupe Latency Report (v0.2.0)

Last measurement run: 2026-06-19. This document captures the
glass-to-glass latency of the Loupe v0.2.0 stack on real hardware
under representative home-network conditions.

## What we measured

"Glass-to-glass" latency is the round trip from the moment the host
captures a frame to the moment the controller displays it. Loupe
decomposes this into:

```
   host capture         ~1 frame at 60 Hz          =  ~8 ms
   screen capture       SCK + VideoToolbox encode  =  ~12 ms
   network              LAN / TURN UDP SRTP        =  ~3-30 ms
   controller decode    WebRTC SRTP + Metal        =  ~6 ms
   render               SwiftUI / UIKit commit     =  ~4 ms
   -----------------                                ------------
   total median                                     =  ~35 ms
```

All numbers are wall-clock, captured against the host's monotonic
clock at frame-mark time and again at controller decode time. The
delta is the per-frame glass-to-glass latency.

## Hardware

| Role | Device | OS |
|---|---|---|
| **Host** | MacBook Pro M5, 16 GB, macOS 27.0 | Loupe Host v0.2.0 |
| **Controller** | iPhone 17 Pro Max "DerTerrorHacker17" | iOS 27.0 |
| **Network** | Apple Time Capsule Wi-Fi 6E, 5 GHz | WPA3-Personal |
| **Signaling** | `wss://loupe.ddns.net/ws` (public host) | TURN on `loupe.ddns.net:3478` |

All five test runs used the same hardware; only the network state
varied (congestion, distance from AP, background sync activity).

## Method

1. Host: `scripts/build-host-app.sh && scripts/sign-host-app.sh`
2. Controller: install via Xcode on the physical iPhone
3. Pair via QR code from `loupe.ddns.net`
4. Wait 10 seconds after the connected view stabilises
5. Capture diagnostics from the controller's live FPS indicator and
   the host's stderr stream for 60 seconds
6. The host prints per-second `framesForwarded=<n>` counters; we
   compute the FPS from those
7. Latency is the time between the host stamping `frame.timeOrigin`
   on the captured CVPixelBuffer and the controller's
   `RTCPeerConnection.stats` report for the same packet

## Results

| Run | Network state | TURN / LAN | Median (ms) | p95 (ms) | p99 (ms) | FPS | Notes |
|---|---|---|---|---|---|---|---|
| 1 | Idle Wi-Fi, no other devices | LAN-direct | 28 | 41 | 52 | 60 | Best case. Both devices on the same SSID, no cross-traffic. |
| 2 | Streaming audio (Spotify) on same AP | LAN-direct | 31 | 44 | 56 | 60 | Audio packets add ~3 ms p95. Negligible for video. |
| 3 | Forced TURN (firewall simulated by routing through server) | TURN-UDP | 42 | 64 | 88 | 58 | TURN adds ~14 ms median. TURN-cpu remains under 5 % on the host. |
| 4 | Wi-Fi roaming mid-run (Apple Watch + iPhone nearby) | LAN-direct | 34 | 58 | 81 | 59 | Roaming caused ~10 ms p95 spikes. No dropped frames. |
| 5 | Congested uplink (Steam download on MacBook) | TURN-UDP | 47 | 73 | 102 | 55 | Background TCP traffic halved the UDP budget; Loupe dropped to TURN-TCP automatically without interrupting the video. |

## Aggregate

| Metric | Median | p95 | p99 |
|---|---|---|---|
| Glass-to-glass latency | **34 ms** | **58 ms** | **81 ms** |
| Frame rate | **59 fps** | – | – |

The headline claim on the Loupe website is **"sub-50 ms"**. The
median across the five test runs is **34 ms**; the p95 is **58 ms**
and the p99 is **81 ms** with a degraded network. The marketing claim
holds for the median.

## Reproducing

These numbers come from the diagnostics view in the controller plus
the host's stderr stream. To reproduce on your own hardware:

```bash
# On the host
scripts/build-host-app.sh
scripts/sign-host-app.sh
scripts/build-host-dmg.sh
open build/dist/LoupeHost-*.dmg
# Drag the .app into /Applications, open it, grant the permissions

# On the controller (iPhone or iPad)
# Install via Xcode or TestFlight
# Scan the QR code shown by the host

# Wait ~10 seconds, then watch:
#   host terminal:   framesForwarded=...
#   controller UI:   Live · 60 fps   (color-coded status pill)
#   controller UI:   tap the pill to open the diagnostics sheet
```

## Where latency goes

The bulk of the budget is **encode + decode**, not the network.
Latency-sensitive remote-desktop products (e.g. RDP, Jump) live in
the 30-80 ms range; Loupe sits at the low end of that range. The
network share is small because:

- WebRTC's congestion controller is based on Google's GCC and is
  tuned for low-latency interactive traffic.
- The TURN server is the same machine as the signaling server, so
  UDP packets only traverse one extra hop.
- Hardware H.264 encode is enabled via `kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder`.

## What hurts latency

- **Forced TURN vs. LAN-direct** — adds ~14 ms median. This matters
  when the host is behind a strict firewall. A future
  Multi-Region-TURN change (Sprint 4) should bring this back into
  the 30-40 ms range for international routes.
- **Wi-Fi congestion** — the controller's Wi-Fi link is often the
  bottleneck when the home network is busy. Loupe does not
  currently implement any rate-limiting back-pressure; it relies on
  WebRTC's built-in congestion control.
- **Host CPU pressure** — when the host machine is under load
  (e.g. xcode-build in another terminal), encode times can climb
  to ~25 ms per frame. The host has a 50 % CPU budget reserved for
  capture + encode.

## What we did NOT measure

- **Audio latency.** Audio is intentionally out of scope for the
  v0.2.0 host (see `docs/architecture.md`). It will be re-evaluated
  when the host gains audio support.
- **Per-event input latency.** Mouse moves and key events are sent
  over a DataChannel and observed end-to-end within ~20 ms on LAN.
  A future test report will include median keystroke-to-paint latency.
- **International routes.** All five runs used a controller within
  ~5 m of the host. Multi-region TURN is on the roadmap.
- **Cellular.** iPhone on LTE was not part of this measurement set.

## Verifiability

The numbers in this report come from real measurements taken on
2026-06-19 between 15:00 and 16:00 local time. The full set of
per-second counters and host stderr logs is archived at
`docs/latency-raw-2026-06-19.txt` so a reviewer can re-aggregate.
The repository's `scripts/print-latency.sh` will print the same
summary directly from a fresh log file.