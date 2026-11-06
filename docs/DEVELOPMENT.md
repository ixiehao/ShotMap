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
python3 scripts/test_native_packaging.py
swift build -c release --arch arm64 --scratch-path .build/package-arm64 -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift build -c release --arch x86_64 --scratch-path .build/package-x86_64 -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
python3 scripts/verify_public_project.py
```

For media-pipeline changes, manually export an authorized H.264/HEVC sample, cancel an active task, retry an output-folder error, and inspect manual frame selection. Check all seven interface languages: English, Simplified Chinese, French, Russian, Spanish, Japanese, and Korean. Confirm English appears first and long labels fit the minimum window size. Synthetic/API tests do not prove that the complete decode-to-export workflow works.

Website-only changes use [WEBSITE.md](WEBSITE.md); documentation-only edits need link and whitespace checks. Neither requires an application release.

### Large queues

Run `swift test --filter LargeQueueLogicTests` for 5,000-path import/deduplication,
ordered drop completion, retry isolation and cancelled provider callbacks. These
are logic tests, not video throughput measurements.

For a local decode-to-export stress run, put at least two authorized H.264/HEVC
videos in a dedicated source folder, then run:

```sh
SHOTMAP_STRESS_MEDIA_DIR=/path/to/licensed-videos \
SHOTMAP_STRESS_OUTPUT_DIR=/path/to/qa-results \
swift test --filter QueueMediaStressTests
```

This creates a unique output subfolder, processes 24 linked video paths mixed
with four invalid files, changes export settings while paused, and cancels an
active decoder in a 1,000-path queue before importing a new queue. The source
files are preserved. Result files remain in the output folder for inspection.
Record the number of distinct source videos separately from the number of
paths. Also check a real large list in the app: complete row ordinals, first and
last entries, scrolling, duplicate import, clear, and window reset. Sample the
Release app's memory separately from the compiler and XCTest process.

## Packaging and assets

[RELEASING.md](RELEASING.md) is the release entry point. Keep the matching source commit, tag, version, DMG and checksum together. Preserve [demo asset provenance](assets/README_DEMO_ASSET.md); use real application outputs rather than fabricated UI screenshots.

## Native builds and future macOS SDKs

Apple Silicon and Intel use the same quality, selection and export policies.
`MediaImageGenerator` owns shared decoder configuration; `VisionComputeSupport`
is the availability-checked device fallback boundary. AVFoundation chooses the
available decoder for the codec and Mac. Vision retains automatic device
selection; a supported CPU retry is reserved for inference-context failures.
Neither the CPU name nor an OS version implies every request has a GPU or Neural
Engine implementation. Do not add parallel generators or weaken frame checks
merely to differentiate the two downloads.

Compile each native target with complete concurrency checking and warnings as
errors. Retain macOS 13.0 deployment compatibility and verify the resulting
Mach-O, rather than inferring the minimum OS from the SDK or build log.
Cross-compiling x86_64 on Apple Silicon does not prove execution on an Intel Mac;
Rosetta testing is also distinct from physical Intel acceptance.

macOS 28 readiness is a validation plan, not a compatibility claim. When its SDK
and test OS are available, add an Apple Silicon test lane for clean launch,
window fitting, seven languages, H.264/HEVC/VFR and rotated video, manual seek,
selection retention, cancellation, export and peak memory. Repeat native Intel
acceptance on a supported Intel OS. Keep newer framework calls behind
availability/capability checks; do not raise the deployment target to match a
new SDK. A native arm64 release must not depend on Rosetta.

Apple's [Rosetta transition notice](https://developer.apple.com/news/?id=w5ngl9k2)
identifies macOS 27 as its final general release. The [asynchronous image
sequence](https://developer.apple.com/documentation/avfoundation/creating-images-from-a-video-asset)
remains the shared decoding interface; no macOS 28-only API is assumed here.
