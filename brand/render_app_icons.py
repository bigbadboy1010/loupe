#!/usr/bin/env python3
"""Generate the full iOS App Icon size matrix from the canonical SVG.

Each entry maps an Apple slot (filename + required pixel dimensions) to
an explicit `qlmanage -s` size. We never round to the nearest available
asset — Apple Xcode asset-catalog validation rejects wrong-sized PNGs.
"""
import os
import shutil
import subprocess

SRC_SVG = "/Users/derterrorhackerai/Desktop/Loupe/brand/loupe-logo/loupe-icon-1024.svg"
OUT_DIR = "/Users/derterrorhackerai/Desktop/Loupe/brand/loupe-logo"

# (apple_filename, required_px)
APPLE_SLOTS = [
    # iPhone (idiom = iphone)
    ("Icon-20@2x.png",    40),   # 20pt @2x
    ("Icon-20@3x.png",    60),   # 20pt @3x
    ("Icon-29@2x.png",    58),   # 29pt @2x
    ("Icon-29@3x.png",    87),   # 29pt @3x
    ("Icon-40@2x.png",    80),   # 40pt @2x
    ("Icon-40@3x.png",   120),   # 40pt @3x
    ("Icon-60@2x.png",   120),   # 60pt @2x
    ("Icon-60@3x.png",   180),   # 60pt @3x
    # iPad (idiom = ipad)
    ("Icon-20-iPad.png",   20),
    ("Icon-20-iPad@2x.png", 40),
    ("Icon-29-iPad.png",   29),
    ("Icon-29-iPad@2x.png", 58),
    ("Icon-40-iPad.png",   40),
    ("Icon-40-iPad@2x.png", 80),
    ("Icon-76.png",        76),
    ("Icon-76@2x.png",    152),
    ("Icon-83.5@2x.png",  167),
    # App Store
    ("Icon-1024.png",    1024),
]


def render(size: int) -> str:
    """Run qlmanage to render the SVG at the exact pixel size and return path."""
    tmp_svg = os.path.join(OUT_DIR, f"_render-{size}.svg")
    shutil.copy(SRC_SVG, tmp_svg)
    subprocess.run(
        ["qlmanage", "-t", "-s", str(size), "-o", OUT_DIR, tmp_svg],
        capture_output=True, text=True, check=True,
    )
    out_png = os.path.join(OUT_DIR, f"_render-{size}.svg.png")
    if not os.path.exists(out_png):
        raise RuntimeError(f"qlmanage did not produce {out_png}")
    return out_png


def main() -> None:
    # Pre-render each required size once, cache in OUT_DIR.
    rendered = {}
    for _, size in APPLE_SLOTS:
        if size not in rendered:
            print(f"  render {size}x{size}")
            rendered[size] = render(size)

    # Map Apple filenames to the matching render.
    print("\n--- installing into AppIcon.appiconset ---")
    DST = (
        "/Users/derterrorhackerai/Desktop/Loupe/apps/LoupeControllerApp/"
        "LoupeControllerApp/Assets.xcassets/AppIcon.appiconset"
    )
    for fname, size in APPLE_SLOTS:
        src = rendered[size]
        dst = os.path.join(DST, fname)
        shutil.copy(src, dst)
        print(f"  {fname:30s} <- {size}x{size}")
    print("\nDone.")


if __name__ == "__main__":
    main()
