#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
readonly project_dir
readonly product_name="ShotMap"
readonly executable_name="ShotMap"
readonly bundle_name="ShotMap_ShotMapApp.bundle"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Packaging/Info.plist")"
readonly version
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$project_dir/Packaging/Info.plist")"
case "$minimum_macos" in
  13.0|13.0.0) ;;
  *) printf 'Expected macOS 13.0 in Packaging/Info.plist, found %s\n' "$minimum_macos" >&2; exit 1 ;;
esac
architecture="all"
output_dir="$project_dir/dist"
preflight_only=false
usage() {
  printf 'Usage: %s [--arch all|arm64|x86_64|universal] [--output-dir PATH] [--preflight-only]\n' "$0"
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch|--output-dir)
      if [[ $# -lt 2 || -z "$2" ]]; then usage >&2; exit 2; fi
      case "$1" in --arch) architecture="$2" ;; --output-dir) output_dir="$2" ;; esac
      shift 2 ;;
    --preflight-only) preflight_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
case "$architecture" in
  all) architectures=(arm64 x86_64) ;;
  arm64|x86_64|universal) architectures=("$architecture") ;;
  *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 2 ;;
esac
# Never merge or replace an existing installer, app, symbols or dangling link.
if [[ -L "$output_dir" || ( -e "$output_dir" && ! -d "$output_dir" ) ]]; then
  printf 'Output must be a real directory: %s\n' "$output_dir" >&2; exit 1
fi
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"
for target in "${architectures[@]}"; do
  destination="$output_dir/ShotMap-$version-$target"
  if [[ -e "$destination" || -L "$destination" ]]; then
    printf 'Refusing to overwrite existing artifacts: %s\nUse a new --output-dir.\n' "$destination" >&2
    exit 1
  fi
done
if "$preflight_only"; then exit 0; fi
if [[ "$architecture" == all ]]; then
  for target in "${architectures[@]}"; do
    /bin/bash "$project_dir/scripts/package_dmg.sh" --arch "$target" --output-dir "$output_dir"
  done
  exit 0
fi
readonly artifact_name="ShotMap-$version-$architecture"
readonly destination="$output_dir/$artifact_name"
# A fail-fast process lock protects SwiftPM output and the shared build-tool
# environment even when separate architectures are invoked concurrently.
readonly lock_dir="$project_dir/.build/package-dmg.lock"
lock_acquired=false
stage=""
readonly volume_name="ShotMap $version $architecture Installer"
readonly scratch_path="$project_dir/.build/package-$architecture"
export MACOSX_DEPLOYMENT_TARGET=13.0
build_args=(-c release --scratch-path "$scratch_path")
case "$architecture" in
  universal) build_args+=(--arch arm64 --arch x86_64) ;;
  *) build_args+=(--arch "$architecture") ;;
esac

validation_device=""
validation_mount=""

verify_binary() {
  python3 "$project_dir/scripts/verify_native_binary.py" --arch "$architecture" \
    --symbols "$symbols_path" "$1"
}

cleanup() {
  if [[ -n "$validation_device" ]]; then
    if ! hdiutil detach "$validation_device" -quiet; then
      printf 'Installer is still mounted; preserving staging files %s and lock %s\n' "$stage" "$lock_dir" >&2
      return
    fi
  fi
  if [[ -n "$validation_mount" ]]; then
    rmdir "$validation_mount" 2>/dev/null || true
  fi
  if [[ -n "$stage" ]]; then
    rm -rf "$stage"
  fi
  if "$lock_acquired"; then
    rm -f "$lock_dir/pid"
    rmdir "$lock_dir"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$project_dir/.build"
if ! mkdir "$lock_dir" 2>/dev/null; then
  printf 'Another packaging run holds %s; retry after it finishes.\n' "$lock_dir" >&2
  exit 75
fi
lock_acquired=true
printf '%s\n' "$$" > "$lock_dir/pid"
# Do not combine a fallible command substitution with readonly: Bash would
# return readonly's status and could turn an empty stage into /ShotMap.app.
stage="$(mktemp -d "$output_dir/.ShotMap-$architecture.XXXXXX")"
readonly stage
readonly app_path="$stage/$product_name.app"
readonly symbols_path="$stage/$product_name.app.dSYM"
readonly dmg_path="$stage/$artifact_name.dmg"
readonly checksum_path="$dmg_path.sha256"
readonly background_path="$stage/.dmg-install-background.png"
readonly iconset_build_dir="$stage/.iconset-build"

cd "$project_dir"
swift build "${build_args[@]}" \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
binary_dir="$(swift build "${build_args[@]}" --show-bin-path)"
readonly binary_dir
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources/Licenses"

ditto "$binary_dir/$executable_name" "$app_path/Contents/MacOS/$executable_name"
# Keep matching crash symbols outside both the installable app and disposable
# build cache. Maintainers can archive this beside the release's source commit.
xcrun dsymutil "$app_path/Contents/MacOS/$executable_name" -o "$symbols_path"
# Remove debugging and local symbol tables from the distributable copy only.
# Runtime code, Swift metadata, and exported symbols remain intact. The original
# build binary stays in .build; the dSYM survives later cache cleanup in dist.
# Signing below covers the final, stripped bytes.
xcrun strip -S -x "$app_path/Contents/MacOS/$executable_name"
verify_binary "$app_path/Contents/MacOS/$executable_name"
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
ditto "ThirdPartyLicenses/TablerIcons-MIT.txt" "$app_path/Contents/Resources/Licenses/TablerIcons-MIT.txt"

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
swift scripts/create_dmg_background.swift "$background_path" "$architecture"
"$packaging_env/bin/dmgbuild" \
  -s scripts/dmg-settings.py \
  -D app="$app_path" \
  -D background="$background_path" \
  "$volume_name" "$dmg_path"
hdiutil verify "$dmg_path"

# A fresh mount path exercises background resolution independently of the
# build-time /Volumes path. Keep Finder closed until validation is complete.
validation_mount="$(mktemp -d /tmp/ShotMap-installer-check.XXXXXX)"
# hdiutil accepts an owned mount point for detach. Do not infer a device from
# localized human-readable output or an Apple_HFS label that can change.
if ! hdiutil attach -readonly -noverify -noautoopen -mountpoint "$validation_mount" "$dmg_path" >/dev/null; then
  # A tool may report failure after attaching. Keep cleanup aware of that mount.
  if [[ -d "$validation_mount/$product_name.app" ]]; then
    validation_device="$validation_mount"
  fi
  printf 'Unable to remount the final DMG for validation.\n' >&2
  exit 1
fi
validation_device="$validation_mount"
"$packaging_env/bin/python3" scripts/verify_dmg_layout.py "$validation_mount" "$product_name.app"
codesign --verify --deep --strict --verbose=2 "$validation_mount/$product_name.app"
verify_binary "$validation_mount/$product_name.app/Contents/MacOS/$executable_name"

hdiutil detach "$validation_device" -quiet
validation_device=""
(cd "$stage" && shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$checksum_path")")

# Record the actual toolchain/source state, not a claim of future OS testing.
python3 - "$stage/build-info.json" "$architecture" "$version" <<'BUILD_INFO'
import json, platform, subprocess, sys
from datetime import datetime, timezone

def output(*args):
    return subprocess.check_output(args, text=True).strip()

with open(sys.argv[1], "w") as file:
    json.dump({
        "version": sys.argv[3], "architecture": sys.argv[2], "minimum_macos": "13.0",
        "source_commit": output("git", "rev-parse", "HEAD"),
        "source_dirty": bool(output("git", "status", "--porcelain")),
        "built_at": datetime.now(timezone.utc).isoformat(),
        "host_architecture": platform.machine(), "host_macos": platform.mac_ver()[0],
        "xcode": output("xcodebuild", "-version"), "swift": output("swift", "--version"),
        "signing": "ad-hoc", "notarized": False,
    }, file, indent=2)
    file.write("\n")
BUILD_INFO
rm -rf "$iconset_build_dir"
rm "$background_path"
# Darwin's exclusive rename atomically publishes the whole verified directory.
# Unlike mv/ditto, it cannot nest into or merge with a destination created by a
# concurrent packaging run after preflight (including an empty dir or symlink).
python3 - "$stage" "$destination" <<'PUBLISH'
import ctypes, os, sys
libc = ctypes.CDLL(None, use_errno=True)
rename = libc.renamex_np
rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
rename.restype = ctypes.c_int
if rename(os.fsencode(sys.argv[1]), os.fsencode(sys.argv[2]), 4) != 0:  # RENAME_EXCL
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error), sys.argv[2])
PUBLISH
printf 'Created %s/%s.dmg\n' "$destination" "$artifact_name"
printf 'Checksum %s/%s.dmg.sha256\n' "$destination" "$artifact_name"
