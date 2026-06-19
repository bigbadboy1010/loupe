# Loupe Brand Assets

Visual identity for **Loupe** — Apple-native remote desktop (macOS ↔ iPhone/iPad).

## Logo

The chosen concept (concept-a-eye) is three concentric circles forming a
lens/aperture, with an Apple-bite cutout on the right edge of the outer
frame. The mark reads simultaneously as:

- A magnifying glass (loupe = French for small magnifying lens)
- An eye / aperture (insight, attention)
- An Apple silhouette with the iconic bite (Apple-native)

Both color and silhouette are designed to remain recognisable at icon
sizes down to 20 × 20 px (notifications, settings).

## Colors

| Role | Hex | sRGB | Notes |
| --- | --- | --- | --- |
| Primary gradient (top) | `#0A2540` | (10, 37, 64) | Deep navy, anchor |
| Primary gradient (bottom) | `#0A84FF` | (10, 132, 255) | System-blue (iOS 17 accent) |
| Highlight gradient (dark mode) | `#3399FF` | (51, 153, 255) | Slightly lifted for dark UI |
| Foreground mark | `#FFFFFF` | (255, 255, 255) | Always pure white for contrast |
| Accent tint (orb, etc.) | `#0A84FF @ 18 %` | — | Same hue, low opacity, for depth |

The full-bleed background uses a 0 → 1 diagonal gradient with a soft
white glow centred near the top to suggest depth without becoming busy.

## Master files

- `loupe-logo/loupe-icon-1024.svg` — iOS master (vector, all sizes derived)
- `loupe-logo/loupe-icon-mac.svg` — macOS master (square, OS applies corner radius)

## iOS app icon size matrix

Apple's `AppIcon.appiconset` requires these specific sizes; all are
generated from the iOS master SVG and installed into the Xcode asset
catalog at `apps/LoupeControllerApp/.../AppIcon.appiconset/`:

| Apple slot | px | Source PNG |
| --- | --- | --- |
| iPhone 20 @2x | 40 | `loupe-icon-40.png` |
| iPhone 20 @3x | 60 | `loupe-icon-60.png` |
| iPhone 29 @2x | 58 | `loupe-icon-60.png` |
| iPhone 29 @3x | 87 | `loupe-icon-80.png` |
| iPhone 40 @2x | 80 | `loupe-icon-80.png` |
| iPhone 40 @3x | 120 | `loupe-icon-120.png` |
| iPhone 60 @2x | 120 | `loupe-icon-120.png` |
| iPhone 60 @3x | 180 | `loupe-icon-180.png` |
| iPad 20 | 20 | `loupe-icon-20.png` |
| iPad 20 @2x | 40 | `loupe-icon-40.png` |
| iPad 29 | 29 | `loupe-icon-29.png` |
| iPad 29 @2x | 58 | `loupe-icon-60.png` |
| iPad 40 | 40 | `loupe-icon-40.png` |
| iPad 40 @2x | 80 | `loupe-icon-80.png` |
| iPad 76 | 76 | `loupe-icon-80.png` |
| iPad 76 @2x | 152 | `loupe-icon-152.png` |
| iPad Pro 83.5 @2x | 167 | `loupe-icon-167.png` |
| App Store | 1024 | `loupe-icon-1024.png` |

## macOS app icon matrix

macOS does not require rounded corners — the OS applies the squircle
mask automatically. The macOS master is intentionally identical to the
iOS one, but is provided as a separate SVG/PNG pair to allow divergent
treatment later if desired.

| macOS slot | px | Source PNG |
| --- | --- | --- |
| App icon (retina) | 1024 | `loupe-icon-mac-1024.png` |
| App icon | 512 | `loupe-icon-mac-512.png` |
| App icon (thumbnail) | 256 | `loupe-icon-mac-256.png` |
| App icon (small) | 128 | `loupe-icon-mac-128.png` |

## Re-generating

```bash
# From brand/ folder on macOS, requires Xcode command-line tools for qlmanage:
cd brand
qlmanage -t -s 1024 -o loupe-logo/ loupe-logo/loupe-icon-1024.svg
qlmanage -t -s 180  -o loupe-logo/ loupe-logo/loupe-icon-1024.svg
# ... repeat for each size in render_app_icons.py

# Install into the Xcode asset catalog:
python3 install_icons.py
```

`render_app_icons.py` and `install_icons.py` are the canonical scripts.

## Licence

The Loupe logo, app icon, and all derived marks are © François (the
project founder), all rights reserved. They are not covered by the
project source-code licence.

If you fork the project, please replace these assets — they identify
the canonical Loupe product.
