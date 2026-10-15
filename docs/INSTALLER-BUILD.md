# Reproducible DMG layout

Run `./scripts/package_dmg.sh` on macOS with Xcode and Python 3.10 or newer.
The script creates an isolated `.build/dmg-tools` environment and installs the
versions in `scripts/dmg-requirements.txt`. These Python dependencies are build
tools only and are never bundled in ShotMap. Set `PACKAGING_PYTHON` if the
desired interpreter is not on PATH or in a standard Homebrew location.

Finder saves view settings asynchronously. A successful AppleScript call or a
correct-looking open Finder window does not prove the disk image contains a
working installation layout. Packaging therefore uses the open-source
[dmgbuild](https://github.com/dmgbuild/dmgbuild) tool to write `.DS_Store`
directly. Version 1.6.7 is required: older releases write a `pBBk` background
bookmark that can make modern Finder show a white background even when the
image alias is valid. The window, icon coordinates, and background are declared in
`scripts/dmg-settings.py`; the background remains project-original artwork.

After compression, the script mounts the final read-only image at a fresh
temporary path. `verify_dmg_layout.py` validates its saved icon view, window
dimensions, icon positions, Applications symlink, and background alias volume
and file identities. Missing metadata fails the build. Application signatures,
both CPU architectures, and the disk image checksum are also verified.

For visual acceptance, eject previous ShotMap installer volumes, open the
new DMG in Finder, and inspect its own installation window. Browsing a volume
inside an existing Finder tab can inherit that tab's view settings. Reopen the
DMG after ejecting it to check the saved layout a second time.

The build tools use MIT licenses; see their upstream sources:
[dmgbuild](https://github.com/dmgbuild/dmgbuild),
[ds_store](https://github.com/dmgbuild/ds_store),
[mac_alias](https://github.com/dmgbuild/mac_alias).
