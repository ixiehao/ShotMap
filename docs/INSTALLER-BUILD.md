# Reproducible DMG layout

Run `./scripts/package_dmg.sh` on macOS with Xcode and Python 3.10 or newer.
The default builds **two independent native installers**, in order: arm64 for
Apple Silicon, then x86_64 for Intel. To build only one:

```sh
./scripts/package_dmg.sh --arch arm64
./scripts/package_dmg.sh --arch x86_64
```

Each target uses `.build/package-<architecture>` and publishes a complete
`dist/ShotMap-<version>-<architecture>/` directory containing:

- `ShotMap-<version>-<architecture>.dmg` and its `.sha256`;
- `ShotMap.app` and its matching `ShotMap.app.dSYM`;
- `build-info.json` with architecture, toolchain, source commit/dirty state,
  minimum OS and signing status.

The app name and bundle identifier stay identical so either installer replaces
the same application. The installer background states the required processor.
All seven languages, fonts, icons and license texts are present in both builds.
The distribution remains ad-hoc signed, without notarization.

Existing output directories, files and symlinks are never overwritten or merged.
Use a new `--output-dir PATH` for a rebuild of the same version. The script
preflights both destinations before starting an `all` build, stages each target
in an owned temporary directory, verifies it, then publishes it with an atomic
exclusive rename. If a later target fails, a previously verified target remains
available. Failures clean only the current invocation's staging files.
A process-owned `.build/package-dmg.lock` prevents concurrent invocations from
mutating the shared SwiftPM outputs or Python environment. A second run fails
immediately with exit status 75; it does not delete the first run's lock. Normal
failure, Ctrl-C and termination release the owned lock. After a forced kill,
inspect its `pid`, confirm that process has ended and eject any installer mount
before removing the stale lock. If an installer cannot be detached, cleanup
preserves both its stage and lock for inspection rather than deleting a mounted
image.

`--preflight-only` checks arguments and output collisions without building.
`--arch universal` remains an explicit compatibility option; the default native
builds do not reuse or thin a previously built universal executable.
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
and file identities. Mount cleanup uses the invocation's own mount point,
without parsing a filesystem label out of localized tool output. Missing
metadata fails the build. Application signatures,
the exact requested CPU slice set, macOS 13.0 in both Launch Services metadata
and each Mach-O slice, matching
dSYM UUIDs and the disk image checksum are also verified. Native packages fail
verification if an unintended second CPU slice is included.

For visual acceptance, eject previous ShotMap installer volumes, open the
new DMG in Finder, and inspect its own installation window. Browsing a volume
inside an existing Finder tab can inherit that tab's view settings. Reopen the
DMG after ejecting it to check the saved layout a second time.

The build tools use MIT licenses; see their upstream sources:
[dmgbuild](https://github.com/dmgbuild/dmgbuild),
[ds_store](https://github.com/dmgbuild/ds_store),
[mac_alias](https://github.com/dmgbuild/mac_alias).
