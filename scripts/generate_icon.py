#!/usr/bin/env python3
"""Generate a canonical AppIcon.iconset for TokenBar.

Apple's `iconutil` requires these exact filenames in the .iconset:
  icon_16x16.png        icon_16x16@2x.png        (32x32)
  icon_32x32.png        icon_32x32@2x.png        (64x64)
  icon_128x128.png      icon_128x128@2x.png      (256x256)
  icon_256x256.png      icon_256x256@2x.png      (512x512)
  icon_512x512.png      icon_512x512@2x.png      (1024x1024)

The status bar uses the same monochrome bitmap (the toolbar tint conveys health).
"""
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow missing; install with: pip3 install Pillow", file=sys.stderr)
    sys.exit(1)

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Resources/AppIcon.iconset")
OUT.mkdir(parents=True, exist_ok=True)

# Monochrome (black with full alpha). macOS will tint as needed for status bar.
COLOR = (0, 0, 0, 255)


def make_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Three vertical bars (left=low, right=high) → looks like a chart/bar glyph.
    # At small sizes, this is still legible.
    n_bars = 3
    bar_w = max(1, size // (2 * n_bars + 2))
    gap = max(1, size // (4 * (n_bars + 1)))
    base = size - size // 6
    heights = [size // 3, size // 2, size * 2 // 3]
    x = size // 6
    for h in heights:
        d.rectangle([x, base - h, x + bar_w, base], fill=COLOR)
        x += bar_w + gap
    return img


# Apple iconset expects these basenames. Each "@2x" is the 2x retina variant.
SIZES = [
    (16,  "icon_16x16.png"),
    (32,  "icon_16x16@2x.png"),
    (32,  "icon_32x32.png"),
    (64,  "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for size, name in SIZES:
    make_icon(size).save(OUT / name)

print(f"Icons written to {OUT}")
