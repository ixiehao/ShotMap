# Quality and localization audit — 2026-10-25

This report records the local QA build based on `3bb3612`, tested with version
0.2.14 / build 24 before release preparation. Its changes are included in
v0.2.15 / build 25. The installed application was left untouched; UI checks used
an isolated app identifier. Release preparation reran all 127 tests successfully
and rebuilt the universal DMG with the new version metadata.

## Changes verified

- Exact frame requests use the submitted `CMTime` instead of a rounded nominal
  frame number. Distinct VFR times stay distinct; shared requests decode once
  and return to every requesting candidate.
- Adding a manual frame batches the same seven sharpness probes, followed by
  one final-size decode. Quality thresholds and selection scores are unchanged.
- Gallery thumbnails decode off the main actor and reuse bounded, display-sized
  bitmaps. Retina scale, portrait images, and aspect-fill crops are considered.
  Offscreen cells and completed live previews release their decoded images.
- History-load failures restore the last successfully displayed record by ID,
  including its filename and edit/save targets. Stale callbacks cannot replace
  newer results. Applying a selection locks selection-changing controls.
- The manual player now actually plays and pauses, synchronizes at 10 Hz,
  captures the actual position when adding a frame, and releases observers and
  its video item when closed. Unneeded AVKit Live Text analysis is disabled.
- Dropped files are collected in their original order and published by batch.
  Consecutive drops retain their arrival order. Import has a visible cancel
  action, a 30-second provider timeout, and protection against late callbacks.
- Batch confirmations close when processing finishes. Confirming a stale Stop
  dialog cannot replace a completed status with Cancelled.
- Grid inputs are bounded to 3×3–8×8. Queue rows preserve stable identities
  without allocating an enumerated copy on each view update.
- The distributable binary omits debug/local symbols; matching dSYM files are
  retained outside the app and build cache. Both architectures, the macOS 13
  target, signatures, and third-party licenses are checked during packaging.

## Seven interface languages

English, Simplified Chinese, French, Russian, Spanish, Japanese, and Korean
each contain 175 resource keys. Arabic was explicitly removed from scope.
The language menu follows this order. Existing preferences remain valid;
first launch matches the first supported system language and falls back to English.

Copy now distinguishes videos, frames, and exported storyboards. It removes
the repeated English brand subtitle, avoids incorrect count grammar, and
no longer describes all processing failures as requiring conversion. Long
labels have room to fit in the narrow inspector; the manual footer button
expands with its text. The editor reserves actual control width before sizing
the player, so its 1000-point minimum window does not push buttons outside.

The three existing product READMEs were updated to describe the seven-language
app. This work does not add website or README translations in four new languages.

## Automated verification

- Baseline: 90 tests passed.
- Updated suite: **127 tests passed, zero failures**, 24.14 seconds on this host.
- Tests include real generated H.264, HEVC and VFR media; exact source timestamps;
  real playback/pause/end; cancellation after decoding starts; all grid sizes;
  PNG/JPEG and both watermarks; thumbnail lifetime; failed and stale preview
  loads; actual `NSItemProvider` callbacks; 900 reverse-order file completions;
  consecutive drops; and timeout/cancel recovery.
- Seven-language checks compare every key and format argument, assert real
  bundled translations, verify regional language matching and fallback, and
  inspect shaped filename glyphs for all supported writing systems.
- Complete Swift concurrency checking and warnings-as-errors passed for the
  universal release build. Public-project checks and shell syntax checks passed.
- The final DMG is remounted to validate its Finder layout, Applications link,
  app signature, both architectures, and macOS 13 minimum version.

## Manual checks on the packaged application

- Main workspace and language menu inspected in all seven languages at the
  940-point minimum main-window width; all seven are present, Arabic is absent.
- Existing saved-result text updates when switching languages.
- Dark → light switching restores foreground and background colors together.
- H.264 3×3 PNG and portrait HEVC 8×8 JPEG generation; time and filename
  watermarks; HEVC manual apply/save produced a decodable 2560×4371 JPEG.
- Manual playback advances the displayed time; adding a frame during playback
  pauses it; stepping a 24 fps source advances by about 0.0417 seconds.
- Smart selection fills 64 slots and Apply saves the selected storyboard.
- Earlier selected frames renumber later selections in chronological order.
- French manual controls and the longer Apply button fit at a 1000-point window.
- A 12-video queue imports in order, pauses after the current video, resumes,
  and retains already written images. The completed-while-confirming edge case
  was found during this check and corrected before the final QA package.
- Final confirmation regression: leave Stop open while eight videos finish;
  the dialog closes automatically and the result remains Complete / Saved: 8.

## Distribution footprint

Compared with the installed 0.2.14 app, the seven-language QA bundle uses about
**20.6% fewer file bytes** (25,544,902 → 20,281,945 bytes).
The universal executable is about 2.97 MB, compared with 8.28 MB previously.
This includes the new functionality and translations; the reduction comes mainly
from removing debug/local symbols from the distributable copy. The compressed
DMG is approximately 16.1 MB. These are storage sizes, not RAM measurements.

## Measured frame-refinement performance

Host: M1 Pro, 8 CPU cores, 16 GB; macOS 27.0.1 (26A434); Xcode 27.0;
Swift 6.4. Release configuration. Each path is warmed up, then old serial and
new batched requests alternate for six measurements. Both paths must select
the same source timestamps. These measurements cover **one-frame sharpness
refinement**, not the whole batch/export pipeline.

| Input | Old serial median | Batched median | Time reduction |
| --- | ---: | ---: | ---: |
| Generated 1280×720 H.264, 30 fps, 20 s | 309.1 ms | 171.9 ms | 44.4% |
| Generated 720×1280 HEVC, 24 fps, 12 s | 103.4 ms | 45.6 ms | 55.9% |
| Local 1010×1026 H.264, 59.94 fps, 16.6 s | 146.1 ms | 83.0 ms | 43.2% |

The complete analysis phase was also timed, after warmup, for three runs:

| Input | 3×3 analysis median | 8×8 analysis median |
| --- | ---: | ---: |
| Generated H.264 | 0.625 s | 0.764 s |
| Generated portrait HEVC | 0.280 s | 0.420 s |
| Local H.264 | 0.355 s | 0.323 s |

Analysis timings exclude image composition and file writing and have no
old-version comparison. Small-grid presentation re-fetches can make 3×3 slower
than 8×8 on a short clip. Do not advertise these values as general export speed.

Reproduce the optional benchmark with:

```sh
SHOTMAP_RUN_FRAME_BENCHMARK=1 swift test -c release \
  --filter MediaPipelineIntegrationTests/testSingleFrameBatchBenchmarkWhenRequested
```

Set `SHOTMAP_BENCHMARK_VIDEO` to a permitted local video to test other media.

## Limits and follow-up

- Intel and macOS 13 compatibility are checked at compile/package level;
  runtime checks here were on Apple Silicon and macOS 27.0.1 only.
- Long-form real HEVC/VFR footage and corrupt-decoder stalls were not benchmarked.
  Cancellation is cooperative and does not promise to interrupt every OS codec stall.
- Process RSS and energy consumption were not used to claim a measured reduction.
  Tests verify bounded bitmap dimensions, reuse, and release rather than unstable
  process-wide allocator/cache readings.
- No new package dependency, bundled model, telemetry, or media upload was added.
  The original font and licenses remain in the app.
- Reusable implementation and localization lessons were added to the shared
  development README, without copying product-specific wording into other apps.
