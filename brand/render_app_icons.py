#!/usr/bin/env python3
"""Generate the full iOS App Icon size matrix from the canonical SVG."""
import os
import shutil
import subprocess

SRC_SVG = "/Users/derterrorhackerai/Desktop/Loupe/brand/loupe-logo/loupe-icon-1024.svg"
OUT_DIR = "/Users/derterrorhackerai/Desktop/Loupe/brand/loupe-logo"

# Apple's required sizes for App Store + iOS 17/18 home screen
SIZES = [
    (1024, "AppStore-1024"),       # App Store master
    (180,  "iPhone-180"),          # iPhone @3x 60pt
    (167,  "iPadPro-167"),         # iPad Pro @2x 83.5pt
    (152,  "iPad-152"),            # iPad @2x 76pt
    (120,  "iPhone-120"),          # iPhone @2x 60pt + Settings @3x 40pt
    (80,   "Spotlight-80"),        # Spotlight @2x 40pt
    (60,   "Notification-60"),     # Notification @1x 20pt
    (40,   "Notification-40"),     # Notification @1x 20pt (smaller variant)
    (29,   "Settings-29"),         # Settings @1x
    (20,   "Notification-20"),     # Notification small
]

for size, label in SIZES:
    out_path = os.path.join(OUT_DIR, f"loupe-icon-{size}.png")
    # Use qlmanage via temp file since it can't take size directly for SVG output naming
    tmp_path = os.path.join(OUT_DIR, f"_tmp-{label}.svg")
    shutil.copy(SRC_SVG, tmp_path)
    subprocess.run(
        ["qlmanage", "-t", "-s", str(size), "-o", OUT_DIR, tmp_path],
        capture_output=True, text=True, check=True,
    )
    # Rename to our convention
    rendered = os.path.join(OUT_DIR, f"_tmp-{label}.svg.png")
    if os.path.exists(rendered):
        os.rename(rendered, out_path)
    os.remove(tmp_path)
    print(f"  {label:20s} -> {size}x{size}  -> {out_path}")

print("\nAll sizes generated.")
