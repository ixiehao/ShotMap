# ShotMap visual identity

The approved ShotMap logo combines an open navy frame, eight horizontal
storyboard tiles and one blue video frame with a white playback triangle.
The same clean geometry is used at large and small sizes. It contains no
landscape illustrations, gradients or third-party brand artwork.

## Canonical artwork

- `Assets/Brand/mark.svg` — transparent light-background mark, viewBox `72 72 384 360`.
- `Assets/Brand/mark-dark.svg` — the same geometry with a light frame for dark backgrounds.
- `Assets/Brand/mark-mono.svg` — single-ink version with a transparent playback triangle.
- `Assets/Brand/app-icon.svg` — the mark on the approved light rounded macOS surface.

Palette: navy `#14253D`, video blue `#1266E8`, playback white `#FFFFFF`.
Dark-interface variants use `#E8F2FF` and `#559BFF`. The eight tiles measure
56 × 32 vector units. The ninth blue frame retains the approved top-right
position; do not add a tenth tile or decorate the individual frames.

## Exports and rendering

Run `python3 scripts/generate_brand_assets.py` on macOS. It produces the
1024px installer/Dock source, the 512px in-app Help resource, the 256px web
icon, SVG and multi-resolution ICO favicons, and website mark variants.
`Assets/Brand/manifest.json` records the derived files and SHA-256 hashes.
The packaging script assembles the ICNS from the 1024px source before signing.

The SwiftUI `ShotMapMarkGlyph` in `StudioControls.swift` draws the approved
coordinates directly, including quadratic corners and an optically centred
playback triangle. It adapts colours to the workspace appearance and avoids
loading a bitmap during frequent view updates. Keep it in sync with the
canonical SVG. Native About uses the bundle ICNS; Help uses the exported PNG.

All seven README files and website language pages use the same identity.
When changing artwork, update asset cache keys and check light and dark
backgrounds, favicon links on nested locale pages, native About, Dock and Finder.

## Interface pictograms

The logo is original project work under the [MIT License](../LICENSE).
Interface pictograms remain unmodified
[Tabler Icons Outline](https://github.com/tabler/tabler-icons) v3.49.0 SVGs,
with the attribution in [NOTICE.md](../NOTICE.md). Do not replace those UI
controls with brand artwork, emoji or a second icon family.

Finder renders the system Applications-folder alias during installation.
Apple-owned system assets are not copied into the repository.
