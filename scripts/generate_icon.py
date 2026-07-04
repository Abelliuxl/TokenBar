#!/usr/bin/env python3
"""Generate 3 monochrome status icons (green/yellow/red bar chart)."""
import os, sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow missing; install with: pip3 install Pillow", file=sys.stderr)
    sys.exit(1)

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Resources/AppIcon.iconset")
OUT.mkdir(parents=True, exist_ok=True)

def make_icon(color, size):
    img = Image.new("RGBA", (size, size), (0,0,0,0))
    d = ImageDraw.Draw(img)
    # 3 vertical bars (left=low, right=high)
    bar_w = size // 6
    gap = size // 12
    base = size - size//8
    heights = [size//4, size//2, size*3//4]
    x = size//6
    for h in heights:
        d.rectangle([x, base-h, x+bar_w, base], fill=color)
        x += bar_w + gap
    return img

for color_name, color in [("green",(46,204,113,255)),
                          ("yellow",(241,196,15,255)),
                          ("red",(231,76,60,255))]:
    for sz in [16, 32, 64, 128, 256, 512]:
        img = make_icon(color, sz)
        # Always use the sized suffix per Apple iconset convention.
        suffix = f"_{sz}x{sz}"
        out = OUT / f"icon_{color_name}{suffix}.png"
        img.save(out)
print(f"Icons written to {OUT}")