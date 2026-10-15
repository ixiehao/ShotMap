#!/bin/bash
set -euo pipefail

readonly project_dir="$(cd "$(dirname "$0")/.." && pwd)"
readonly product_name="ShotMap"
readonly executable_name="ShotTessera"
readonly bundle_name="ShotTessera_ShotTesseraApp.bundle"
readonly version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Packaging/Info.plist")"
# A versioned Finder volume avoids colliding with a user's still-open older
# installer. Finder resolves a duplicate disk by its internal name, which can
# otherwise write the layout into the wrong, read-only image.
readonly volume_name="ShotMap $version Installer"
readonly output_dir="$project_dir/dist"
readonly app_path="$output_dir/$product_name.app"
readonly dmg_path="$output_dir/ShotMap-$version.dmg"
readonly checksum_path="$dmg_path.sha256"
readonly background_path="$output_dir/.dmg-install-background.png"
readonly iconset_build_dir="$output_dir/.iconset-build"

validation_device=""
validation_mount=""

cleanup() {
  if [[ -n "$validation_device" ]]; then
    hdiutil detach "$validation_device" -quiet || true
  fi
  if [[ -n "$validation_mount" ]]; then
    rmdir "$validation_mount" 2>/dev/null || true
  fi
  rm -rf "$iconset_build_dir"
}

trap cleanup EXIT

cd "$project_dir"
swift build -c release --arch arm64 --arch x86_64

readonly binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
# Recreate the bundle on every run. `ditto` merges into an existing directory,
# which could otherwise leave files from an earlier build in a release DMG.
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources/Licenses"

ditto "$binary_dir/$executable_name" "$app_path/Contents/MacOS/$executable_name"
readonly binary_architectures="$(lipo -archs "$app_path/Contents/MacOS/$executable_name")"
if [[ " $binary_architectures " != *" arm64 "* || " $binary_architectures " != *" x86_64 "* ]]; then
  printf 'Expected a universal arm64 + x86_64 binary.\n' >&2
  exit 1
fi
ditto "$binary_dir/$bundle_name" "$app_path/Contents/Resources/$bundle_name"
ditto "Packaging/Info.plist" "$app_path/Contents/Info.plist"

# A classic ICNS preserves the source image's transparent canvas. Icon
# Composer's automatic surface adds a bright, full-size squircle on recent
# macOS releases, which makes this app look oversized in the Dock even when
# the visible mark itself is scaled down.
rm -rf "$iconset_build_dir"
mkdir -p "$iconset_build_dir/AppIcon.iconset"
while IFS=: read -r filename pixels; do
  sips --resampleHeightWidth "$pixels" "$pixels" "Assets/AppIcon-1024-source.png" \
    --out "$iconset_build_dir/AppIcon.iconset/$filename" >/dev/null
done <<'ICON_SIZES'
icon_16x16.png:16
icon_16x16@2x.png:32
icon_32x32.png:32
icon_32x32@2x.png:64
icon_128x128.png:128
icon_128x128@2x.png:256
icon_256x256.png:256
icon_256x256@2x.png:512
icon_512x512.png:512
icon_512x512@2x.png:1024
ICON_SIZES
iconutil --convert icns --output "$iconset_build_dir/AppIcon.icns" "$iconset_build_dir/AppIcon.iconset"
test -f "$iconset_build_dir/AppIcon.icns"
ditto "$iconset_build_dir/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
ditto "LICENSE" "$app_path/Contents/Resources/Licenses/MIT-LICENSE.txt"
ditto "NOTICE.md" "$app_path/Contents/Resources/Licenses/NOTICE.md"
ditto "ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt" "$app_path/Contents/Resources/Licenses/NotoSansCJK-OFL-1.1.txt"

codesign --force --sign - --timestamp=none "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

# dmgbuild writes .DS_Store synchronously, without a Finder GUI session or
# cached window state. Packaging must fail if this layout cannot be validated.
readonly packaging_env="$project_dir/.build/dmg-tools"
# dmgbuild 1.6.7 requires Python 3.10+. Xcode's /usr/bin/python3 can still be
# 3.9; discover a supported interpreter instead of silently installing an old
# dmgbuild with broken modern-Finder background bookmarks.
packaging_python=""
for candidate in "${PACKAGING_PYTHON:-python3}" /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  if "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
    packaging_python="$candidate"
    break
  fi
done
if [[ -z "$packaging_python" ]]; then
  printf 'Packaging requires Python 3.10 or newer; set PACKAGING_PYTHON to its executable.\n' >&2
  exit 1
fi
if [[ -x "$packaging_env/bin/python3" ]] && ! "$packaging_env/bin/python3" -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
  rm -rf "$packaging_env"
fi
if [[ ! -x "$packaging_env/bin/python3" ]]; then
  "$packaging_python" -m venv "$packaging_env"
fi
"$packaging_env/bin/python3" -m pip install --disable-pip-version-check -q -r scripts/dmg-requirements.txt
swift scripts/create_dmg_background.swift "$background_path"
"$packaging_env/bin/dmgbuild" \
  -s scripts/dmg-settings.py \
  -D app="$app_path" \
  -D background="$background_path" \
  "$volume_name" "$dmg_path"
hdiutil verify "$dmg_path"

# A fresh mount path exercises background resolution independently of the
# build-time /Volumes path. Keep Finder closed until validation is complete.
validation_mount="$(mktemp -d /tmp/ShotMap-installer-check.XXXXXX)"
validation_output="$(hdiutil attach -readonly -noverify -noautoopen -mountpoint "$validation_mount" "$dmg_path")"
validation_device="$(printf '%s\n' "$validation_output" | awk '/Apple_HFS/ { print $1; exit }')"
if [[ -z "$validation_device" || ! -d "$validation_mount" ]]; then
  printf 'Unable to remount the final DMG for validation.\n' >&2
  exit 1
fi
"$packaging_env/bin/python3" scripts/verify_dmg_layout.py "$validation_mount" "$product_name.app"
codesign --verify --deep --strict --verbose=2 "$validation_mount/$product_name.app"
readonly packaged_architectures="$(lipo -archs "$validation_mount/$product_name.app/Contents/MacOS/$executable_name")"
if [[ " $packaged_architectures " != *" arm64 "* || " $packaged_architectures " != *" x86_64 "* ]]; then
  printf 'Final DMG does not contain a universal arm64 + x86_64 app.\n' >&2
  exit 1
fi

hdiutil detach "$validation_device" -quiet
validation_device=""
(cd "$output_dir" && shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$checksum_path")")

printf 'Created %s\n' "$dmg_path"
printf 'Checksum %s\n' "$checksum_path"
