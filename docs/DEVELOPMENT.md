# Developing ShotMap

[Documentation index](README.md) · [Architecture](ARCHITECTURE.md)

## Repository layout

- `Package.swift`, `Sources/`, `Tests/` — native application package and tests.
- `scripts/` — packaging and public-project checks; use the exact lowercase directory name.
- `website/` — official website and localized page generation.
- `docs/` — architecture, naming, verification and publishing guides.

Use macOS and the Swift toolchain required by `Package.swift`. Keep the product name, Swift package, executable and bundle identifier consistent with [NAMING.md](NAMING.md); do not globally replace identifiers based on the displayed app name.

## Validation

From the repository root:

```sh
swift test
swift build -c release --arch arm64 --arch x86_64 -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
python3 scripts/verify_public_project.py
```

For media-pipeline changes, manually export an authorized H.264/HEVC sample, cancel an active task, retry an output-folder error, and inspect manual frame selection. Check all seven interface languages: English, Simplified Chinese, French, Russian, Spanish, Japanese, and Korean. Confirm English appears first and long labels fit the minimum window size. Synthetic/API tests do not prove that the complete decode-to-export workflow works.

Website-only changes use [WEBSITE.md](WEBSITE.md); documentation-only edits need link and whitespace checks. Neither requires an application release.

## Packaging and assets

[RELEASING.md](RELEASING.md) is the release entry point. Keep the matching source commit, tag, version, DMG and checksum together. Preserve [demo asset provenance](assets/README_DEMO_ASSET.md); use real application outputs rather than fabricated UI screenshots.
