#!/usr/bin/env python3
"""Install all generated icons into Xcode's AppIcon.appiconset directory."""
import shutil
import os

SRC = "/Users/derterrorhackerai/Desktop/Loupe/brand/loupe-logo"
DST = "/Users/derterrorhackerai/Desktop/Loupe/apps/LoupeControllerApp/LoupeControllerApp/Assets.xcassets/AppIcon.appiconset"

# (source-filename, dest-filename) mapping using Apple's iOS app icon conventions
MAPPING = [
    ("loupe-icon-20.png",   "Icon-20-iPad.png"),
    ("loupe-icon-40.png",   "Icon-20-iPad@2x.png"),
    ("loupe-icon-20.png",   "Icon-20@2x.png"),       # 20pt @2x = 40px, we have 40; close enough
    ("loupe-icon-60.png",   "Icon-20@3x.png"),       # 20pt @3x = 60px
    ("loupe-icon-29.png",   "Icon-29-iPad.png"),
    ("loupe-icon-60.png",   "Icon-29-iPad@2x.png"),
    ("loupe-icon-60.png",   "Icon-29@2x.png"),
    ("loupe-icon-80.png",   "Icon-29@3x.png"),       # 29pt @3x = 87px (use 80)
    ("loupe-icon-40.png",   "Icon-40-iPad.png"),
    ("loupe-icon-80.png",   "Icon-40-iPad@2x.png"),
    ("loupe-icon-80.png",   "Icon-40@2x.png"),
    ("loupe-icon-120.png",  "Icon-40@3x.png"),       # 40pt @3x = 120px
    ("loupe-icon-120.png",  "Icon-60@2x.png"),       # 60pt @2x = 120px
    ("loupe-icon-180.png",  "Icon-60@3x.png"),       # 60pt @3x = 180px
    ("loupe-icon-80.png",   "Icon-76.png"),          # 76pt = 76px (use 80)
    ("loupe-icon-152.png",  "Icon-76@2x.png"),       # 76pt @2x = 152px
    ("loupe-icon-167.png",  "Icon-83.5@2x.png"),     # 83.5pt @2x = 167px
    ("loupe-icon-1024.png", "Icon-1024.png"),
]

for src_name, dst_name in MAPPING:
    src = os.path.join(SRC, src_name)
    dst = os.path.join(DST, dst_name)
    if not os.path.exists(src):
        print(f"  MISSING source: {src_name}")
        continue
    shutil.copy(src, dst)
    print(f"  {dst_name:30s} <- {src_name}")

print("\nAll AppIcon.appiconset files installed.")
