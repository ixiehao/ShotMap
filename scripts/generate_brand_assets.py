#!/usr/bin/env python3
"""Export approved ShotMap vectors for the app, installer, web and docs.

Requires macOS sips. No third-party renderer, fonts or image generation.
The application ICNS is assembled from the 1024px source by package_dmg.sh.
"""
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'Assets/Brand'

def resized_svg(source, pixels):
    return re.sub(r'width="512" height="512"', f'width="{pixels}" height="{pixels}"', source, count=1)

def export(source, target, pixels, scratch):
    svg = scratch / f'icon-{pixels}.svg'
    svg.write_text(resized_svg(source, pixels))
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['sips', '-s', 'format', 'png', str(svg), '--out', str(target)], check=True, capture_output=True)

def main():
    app = (BRAND / 'app-icon.svg').read_text()
    for source in BRAND.glob('*.svg'):
        ET.parse(source)
    outputs = []
    with tempfile.TemporaryDirectory(prefix='ShotMap-brand-export-') as temp:
        scratch = Path(temp)
        for relative, pixels in [
            ('Assets/AppIcon-1024-source.png', 1024),
            ('Sources/ShotMapApp/Resources/AppIcon.png', 512),
            ('website/assets/app-icon.png', 256),
        ]:
            path = ROOT / relative
            export(app, path, pixels, scratch)
            outputs.append(path)
        # Multi-resolution ICO stores PNG payloads without a lossy conversion.
        sizes = [16, 32, 48, 256]
        blobs = []
        for pixels in sizes:
            target = scratch / f'icon-{pixels}.png'
            export(app, target, pixels, scratch)
            blobs.append(target.read_bytes())
        offset = 6 + 16 * len(sizes)
        directory = bytearray(struct.pack('<HHH', 0, 1, len(sizes)))
        for size, data in zip(sizes, blobs):
            directory += struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(data), offset)
            offset += len(data)
        ico = ROOT / 'website/favicon.ico'
        ico.write_bytes(directory + b''.join(blobs))
        outputs.append(ico)
    for source, target in [('app-icon.svg', 'website/favicon.svg'),
                           ('mark.svg', 'website/assets/brand-mark.svg'),
                           ('mark-dark.svg', 'website/assets/brand-mark-dark.svg')]:
        path = ROOT / target
        path.write_text((BRAND / source).read_text())
        outputs.append(path)
    manifest = {'identity': 'ShotMap outer frame with video keyframe',
                'approved': '2026-11-01', 'geometry': 'eight horizontal frames plus one blue playback frame',
                'outputs': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in outputs}}
    (BRAND / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(f'Exported {len(outputs)} brand assets from Assets/Brand.')

if __name__ == '__main__':
    main()
