"""Render icon/AppIcon.svg into the AppIcon asset catalog.

    uv run --with cairosvg macos/icon/make_icons.py
"""

import json
import pathlib

import cairosvg

HERE = pathlib.Path(__file__).parent
OUT = HERE.parent / "App" / "Assets.xcassets" / "AppIcon.appiconset"
SVG = (HERE / "AppIcon.svg").read_bytes()

images = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        px = points * scale
        cairosvg.svg2png(bytestring=SVG, write_to=str(OUT / name), output_width=px, output_height=px)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})

(OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
(OUT.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
print(f"wrote {len(images)} icons to {OUT}")
