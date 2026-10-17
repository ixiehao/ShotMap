# ShotMap Iris icon

`ShotMap Iris` is the original visual identity for ShotMap. It combines an
abstract eye-shaped viewfinder with a 3 x 3 field of rounded storyboard tiles.
The dark central pupil means visual selection; its small gold highlight means
the chosen representative frame. It intentionally avoids play buttons, camera
bodies, film sprockets, letters, and third-party marks.

## Palette

- Indigo base: `#111B34` to `#263D73`
- Viewfinder edge: `#EAF5FF`
- Tile family: cyan, cool blue, periwinkle, and mint
- Selection highlight: `#FFD174`

## Files

- `Assets/AppIcon-1024-source.png` — canonical original project artwork for the macOS app icon.
- `Sources/ShotMapApp/Resources/AppIcon.png` — runtime mark shown inside the app UI, optically enlarged for small in-app placements.

The packaging script creates a standard `.icns` only inside the app and DMG at
package time. This preserves the source artwork's transparent canvas in the
Dock; the system no longer adds a separate Icon Composer surface around it.

The complete visible mark is optically scaled to about 60% on a transparent
canvas. This intentionally reduces both the navy surface and the eye artwork,
giving the Dock a comparable visual footprint to neighbouring macOS apps.
The in-app resource deliberately uses the same artwork at a larger optical
size, so sidebar, empty-state, Help, and About icons remain legible.

The icon was generated from an original art direction for this project and is
distributed with the repository under its MIT license.

## Interface pictograms

The interface uses bundled [Tabler Icons Outline](https://github.com/tabler/tabler-icons)
SVGs as native template images. Their strokes adapt to the current light or
dark appearance. The unmodified third-party assets and their MIT attribution
are documented in [NOTICE.md](../NOTICE.md).

The only non-project symbols visible during installation are macOS-owned
system UI: Finder renders the Applications-folder alias and the Dock itself.
Those system assets are not copied into or distributed by this repository.
