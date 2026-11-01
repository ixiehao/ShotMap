#!/usr/bin/env python3
"""Build public derivatives from visually verified, complete app captures.

Development-only dependency: Pillow. This does not ship inside ShotMap.
No UI is drawn, replaced, stretched, or cropped by this script.
"""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parent.parent
LANGUAGES = ("en", "zh", "fr", "ru", "es", "ja", "ko")
records = []


def derivative(source, destination, width, *, png=False):
    image = Image.open(source).convert("RGB")
    source_size = image.size
    image = image.resize((width, round(width * image.height / image.width)), Image.Resampling.LANCZOS)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if png:
        image.save(destination, optimize=True)
    else:
        image.save(destination, quality=88, method=6)
    records.append({
        "path": str(destination.relative_to(ROOT)),
        "pixels": list(image.size),
        "bytes": destination.stat().st_size,
        "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
        "source": source.name,
        "sourcePixels": list(source_size),
        "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "processing": "Proportional reduction and encoding; complete captured window retained",
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captures", type=Path)
    parser.add_argument("storyboard", type=Path, help="Actual image exported by ShotMap")
    args = parser.parse_args()
    assets = ROOT / "website/assets"
    docs = ROOT / "docs/assets"
    for language in LANGUAGES:
        for kind, width in (("workspace", 1800), ("manual", 1600)):
            source = args.captures / f"{kind}-{language}.jpg"
            if Image.open(source).width < 2000:
                raise ValueError(f"Unexpected capture size: {source}")
            derivative(source, assets / f"{kind}-{language}.webp", width)
        derivative(args.captures / f"workspace-{language}.jpg", docs / f"readme-workspace-{language}.png", 1280, png=True)

    derivative(args.captures / "app-launch-en.jpg", assets / "app-launch-screen.webp", 1600)
    derivative(args.captures / "workspace-dark-en.jpg", assets / "workspace-dark-en.webp", 1800)
    derivative(args.captures / "preview-focus-en.jpg", assets / "video-to-storyboard-overview.webp", 1600)
    derivative(args.captures / "manual-ja.jpg", assets / "workflow-ja.webp", 1600)
    derivative(args.captures / "about-en.jpg", assets / "about-en.webp", 568)
    derivative(args.storyboard, assets / "tears-of-steel-storyboard.webp", 1400)
    derivative(args.captures / "manual-en.jpg", docs / "video-to-storyboard-demo.png", 1280, png=True)
    derivative(args.captures / "preview-focus-en.jpg", docs / "video-to-storyboard-overview.png", 1280, png=True)

    # Condensed real UI states, with a common canvas so no window is cropped.
    frames = []
    for name in ("workspace-en", "manual-check-en", "manual-en", "workspace-en"):
        image = Image.open(args.captures / f"{name}.jpg").convert("RGB")
        fitted = ImageOps.contain(image, (960, 622), Image.Resampling.LANCZOS)
        frame = Image.new("RGB", (960, 622), "#f3f5fa")
        frame.paste(fitted, ((960 - fitted.width) // 2, (622 - fitted.height) // 2))
        frames.append(frame.quantize(colors=192))
    gif = docs / "video-to-storyboard-demo.gif"
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=[1800, 2300, 2600, 2000], loop=0, disposal=2, optimize=True)
    records.append({"path": str(gif.relative_to(ROOT)), "pixels": [960, 622], "bytes": gif.stat().st_size,
                    "sha256": hashlib.sha256(gif.read_bytes()).hexdigest(),
                    "processing": "Condensed sequence of real captured UI states; each full window fits the canvas"})
    manifest = {
        "appVersion": "0.2.17 (27)", "captureDate": "2026-11-01", "languages": list(LANGUAGES),
        "footage": {"title": "Tears of Steel (2012)", "credit": "Blender Foundation / Blender Institute",
                    "license": "CC BY 3.0", "licenseURL": "https://creativecommons.org/licenses/by/3.0/",
                    "projectURL": "https://mango.blender.org/",
                    "sourceSHA256": "efa9062d9cdb7a338e40ad530dfdf234806743f29ae6a1a136b97ece4e588e8f"},
        "assets": records,
    }
    (docs / "demo-assets.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for item in records:
        print(f"{item['bytes'] // 1024:4} KB  {item['path']}")


if __name__ == "__main__":
    main()
