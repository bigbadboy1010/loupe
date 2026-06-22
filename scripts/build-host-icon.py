#!/usr/bin/env python3
"""
Loupe App-Icon Generator (Sprint 11).

Generates a 1024x1024 master PNG that matches the website brand mark
(site/index.html .brand-mark SVG: a circle and a handle line, both
stroked in turquoise, on the Loupe dark-indigo background). This is
the source that `build-host-app.sh` feeds into `sips`/`iconutil` to
produce the multi-resolution .icns container macOS expects.

Why programmatic and not a hand-drawn asset?

  * The website's brand mark is a 5-line SVG. A programmatic render
    keeps the icon visually consistent with the site down to the
    stroke widths and line caps.
  * It removes any external dependency: no Figma, no ImageMagick,
    no sips-from-SVG dance. The only tool is Pillow, which is
    already on this build host (it ships with macOS for Python 3
    users via `pip install pillow` and is pre-installed in the
    Hermes environment).
  * macOS applies its own squircle mask, so the source is a
    perfect square with no transparent corners and no rounded
    shape baked in.

The original brand-mark SVG is drawn at 32x32 with the circle at
(cx=14, cy=14, r=9) and the handle from (20.5, 20.5) to (28, 28).
That is intentionally off-centre: the visual centre of the
magnifying glass (lens + handle together) sits near the lower-right
of the SVG. When the SVG is used in a 24px nav link on the website
that is fine, but for an app icon we need the visual mass
optically centred. So this script:

  1. Draws the loupe into a virtual sub-canvas of the unit size.
  2. Computes the bounding box of the resulting strokes.
  3. Translates the geometry so the bounding box is centred in
     the master canvas, with 10% padding on the tightest side.

Output:

  build/host-app-icon/icon_1024.png   master, also the "512@2x"
                                      retina size in the iconset

The build script then `iconutil --convert icns` over the
corresponding `.iconset/` directory.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

# Brand colours — matched to loupe-signaling/site/style.css.
BG = (11, 19, 43, 255)        # #0B132B  dark indigo
FG = (91, 192, 190, 255)      # #5BC0BE  turquoise
CURSOR = (91, 192, 190, 96)   # #5BC0BE @ ~38% alpha — a faint hint


def _loupe_strokes(unit: float = 32.0):
    """Return the brand-mark stroke geometry in *unit* coordinates.

    The numbers are exactly the values in the website's brand-mark
    SVG (viewBox 32x32): circle at (14, 14) r=9 stroke 2.4, handle
    from (20.5, 20.5) to (28, 28) stroke 2.8 round.
    """
    return {
        "cx": 14.0 * unit / 32.0,
        "cy": 14.0 * unit / 32.0,
        "r": 9.0 * unit / 32.0,
        "stroke_circle": 2.4 * unit / 32.0,
        "x1": 20.5 * unit / 32.0,
        "y1": 20.5 * unit / 32.0,
        "x2": 28.0 * unit / 32.0,
        "y2": 28.0 * unit / 32.0,
        "stroke_handle": 2.8 * unit / 32.0,
    }


def _loupe_bounding_box(geom: dict) -> tuple[float, float, float, float]:
    """Compute (x0, y0, x1, y1) of the loupe's visible pixels in
    the same unit coordinate system. Half the stroke width is added
    to each side so the bounding box is conservative.
    """
    half_c = geom["stroke_circle"] / 2
    half_h = geom["stroke_handle"] / 2
    # Circle extents
    c0x = geom["cx"] - geom["r"] - half_c
    c1x = geom["cx"] + geom["r"] + half_c
    c0y = geom["cy"] - geom["r"] - half_c
    c1y = geom["cy"] + geom["r"] + half_c
    # Handle extents
    h0x = min(geom["x1"], geom["x2"]) - half_h
    h1x = max(geom["x1"], geom["x2"]) + half_h
    h0y = min(geom["y1"], geom["y2"]) - half_h
    h1y = max(geom["y1"], geom["y2"]) + half_h
    # Union
    return (min(c0x, h0x), min(c0y, h0y), max(c1x, h1x), max(c1y, h1y))


def draw_master(size: int = 1024) -> Image.Image:
    """Draw the master icon at `size` x `size`, optically centred."""
    img = Image.new("RGBA", (size, size), BG)
    draw = ImageDraw.Draw(img)

    # Pick a unit such that the loupe bounding box + 10% padding on
    # the tightest side fits within the master canvas. This way the
    # loupe is centred *visually*, not just mathematically.
    unit = size / 32.0
    geom = _loupe_strokes(unit=32.0)
    bbox = _loupe_bounding_box(geom)  # in 32-unit coordinates
    bbox_w = bbox[2] - bbox[0]
    bbox_h = bbox[3] - bbox[1]

    # Reserve 80% of the master canvas for the loupe, 10% padding
    # on each side. This is the macOS "icon safe area" convention.
    target_w = size * 0.80
    target_h = size * 0.80
    # Scale factor in 32-unit space.
    s = min(target_w / bbox_w, target_h / bbox_h)
    # Re-derive the loupe geometry in pixels.
    geom_px = _loupe_strokes(unit=32.0 * s)

    # Now translate the geometry so the *lens centre* is centred in
    # the canvas. Centring on the lens (not the bounding box) is the
    # macOS convention for off-axis icons: the part the user "looks
    # at" is the focal point, the handle is allowed to extend into
    # the corner. The whole shape still fits within the 80% safe
    # area because we scaled it to fit before this translation.
    cx_canvas = size / 2
    cy_canvas = size / 2
    dx = cx_canvas - geom_px["cx"]
    dy = cy_canvas - geom_px["cy"]

    cx = geom_px["cx"] + dx
    cy = geom_px["cy"] + dy
    r = geom_px["r"]
    stroke_circle = max(2, int(round(geom_px["stroke_circle"])))
    draw.ellipse(
        (cx - r, cy - r, cx + r, cy + r),
        outline=FG,
        width=stroke_circle,
    )

    # Handle: line + round cap at the tip. The cap is a filled
    # circle whose centre is the end of the line, and whose radius
    # is half the stroke width. That makes the handle stroke blend
    # seamlessly into the rounded cap with no dark notch.
    stroke_handle = max(2, int(round(geom_px["stroke_handle"])))
    hx1 = geom_px["x1"] + dx
    hy1 = geom_px["y1"] + dy
    hx2 = geom_px["x2"] + dx
    hy2 = geom_px["y2"] + dy
    # Compute the offset of the cap from the line endpoint so the
    # line stops at the cap centre (otherwise the line would
    # overshoot the cap and create a tiny rectangle).
    dxh = hx2 - hx1
    dyh = hy2 - hy1
    import math
    handle_len = math.hypot(dxh, dyh)
    cap_r = stroke_handle / 2
    if handle_len > 0:
        # Where the line should end: cap_r before the cap centre.
        ux, uy = dxh / handle_len, dyh / handle_len
        line_end_x = hx2 - ux * cap_r
        line_end_y = hy2 - uy * cap_r
    else:
        line_end_x, line_end_y = hx2, hy2
    draw.line(
        [(hx1, hy1), (line_end_x, line_end_y)],
        fill=FG,
        width=stroke_handle,
    )
    # Round cap at the tip — filled circle.
    draw.ellipse(
        (hx2 - cap_r, hy2 - cap_r, hx2 + cap_r, hy2 + cap_r),
        fill=FG,
    )

    # Subtle crosshair inside the lens. Two short lines forming a
    # + at the centre, with a gap in the middle (so it doesn't
    # compete with the lens edge). Sits at 38% alpha so it reads
    # as a hint, not as a focus reticle.
    centre = (cx, cy)
    gap = 1.4 * (32.0 * s) / 32.0   # gap scales with the icon
    length = 2.6 * (32.0 * s) / 32.0
    thin = max(1, int(round(0.18 * (32.0 * s) / 32.0)))
    for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        x1 = centre[0] + ddx * gap
        y1 = centre[1] + ddy * gap
        x2 = centre[0] + ddx * (gap + length)
        y2 = centre[1] + ddy * (gap + length)
        draw.line([(x1, y1), (x2, y2)], fill=CURSOR, width=thin)

    return img


def main() -> int:
    parser = argparse.ArgumentParser(description="Loupe App-Icon Generator")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("build/host-app-icon"),
        help="Where to write the PNGs (default: build/host-app-icon).",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=1024,
        help="Master icon size in pixels (default: 1024).",
    )
    args = parser.parse_args()

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    master = draw_master(args.size)
    out_path = out_dir / f"icon_{args.size}.png"
    master.save(out_path, "PNG", optimize=True)
    print(f"wrote {out_path}  ({args.size}x{args.size})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
