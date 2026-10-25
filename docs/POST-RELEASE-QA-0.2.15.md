# ShotMap v0.2.15 — independent post-release QA

Date: 2026-10-25. Source/tag: `8f59c920191299c613f2b4408386a260b502d9dd`
/ `v0.2.15`, build 25. This is a new test run, separate from the earlier
[pre-release audit](QUALITY-AUDIT-2026-10-25.md).

**Result for the released v0.2.15:** the automated suite and tested core workflows passed. One reproducible
P2 error-recovery guidance defect remains: a non-video file named `.mp4` is
incorrectly presented as needing conversion. No crash, lost export, or queue
blocking was observed in the scenarios below. This is not a claim of exhaustive
coverage or absence of other bugs.

The source fix and its regression checks are recorded in the
[2026-10-26 follow-up](#source-fix-follow-up--2026-10-26) below.

## Environment and isolation

- Apple M1 Pro, 16 GB RAM; macOS 27.0.1 (26A434); Apple Swift 6.4.
- The repository was clean at the start. No production source was changed.
- UI testing used a copy of the app extracted from the final DMG. Only its
  display name and bundle identifier were changed, then it was ad-hoc re-signed:
  `com.ixiehao.shotmap.releaseqa20261025b`. Executable and resources were retained.
- All inputs and outputs were in a new disposable test directory. The installed
  `/Applications/ShotMap.app`, user videos, and global language/theme were not
  changed. The isolated app was quit and the read-only fixture directory restored
  to mode 0755 after testing. The test DMG was detached.

## Automated and package checks performed in this run

| Check | Result |
| --- | --- |
| `swift test` | **127 tests, zero failures**, 42.877 seconds reported by XCTest |
| Codec and lifecycle integration tests | H.264, HEVC, VFR, real playback, cancellation, preview/save lifecycle, ordered providers, timeouts and resource checks passed as part of that run |
| Seven-language resource tests | Keys, format arguments, language matching/fallback and filename glyph coverage passed |
| DMG SHA-256 and `hdiutil verify` | Passed |
| Final mounted DMG Finder layout and Applications link | `scripts/verify_dmg_layout.py` passed |
| App resource signature | `codesign --verify --deep --strict` passed; signature is **ad-hoc**, not Apple notarization |
| Binary and metadata | `arm64` + `x86_64`; both declare macOS 13.0 minimum; version 0.2.15/build 25 |
| Packaged languages/licenses | Exactly `en`, `zh-Hans`, `fr`, `ru`, `es`, `ja`, `ko`; four license/notice files retained |
| Export-file validation | **21 generated PNG/JPEG files** decoded with FFmpeg; every image had width 2560 and a valid positive height |

The opt-in benchmark test was not enabled. Its presence in the passing suite does
not constitute a new performance benchmark. No percentage speed improvement,
memory reduction, or energy claim is made from this run.

## Real application workflows

| Scenario | Observation |
| --- | --- |
| Mixed five-file import | Order retained: invalid MP4, generated H.264, portrait HEVC, three-frame/0.10 s H.264, generated VFR H.264 |
| Mixed batch export | Four valid inputs saved; invalid input failed without stopping the later videos. Final state: Saved 4 / Failed 1 |
| Watermarks and formats | Both filename and timestamp watermarks rendered; PNG and JPEG exports decoded successfully |
| In-progress preview | Frame tiles and captured-frame count were visible during generation before the completed exported image replaced them. Individual tile arrival timing was not measured |
| VFR manual editor | Playback advanced, Add current frame paused playback and added a candidate, and the editor remained responsive |
| Selection ordering | Selecting a later frame before an earlier frame renumbered chronologically. Removing the earliest selection renumbered the remaining selections consecutively |
| Time entry bounds | Invalid `99:99:99.999` restored the prior value; valid but out-of-range `23:00:00.000` clamped to the video end and disabled forward stepping |
| Manual apply/save | Smart select filled 9/9 slots; Apply saved a new `vfr-motion-shot-002.png` without overwriting the original |
| Close/cancel while loading | Requesting new candidates and immediately cancelling returned safely to the existing saved result; later operations did not change its file hash |
| Read-only output folder | Generation kept a usable preview when automatic saving failed; Save As to a writable directory succeeded and removed the failure state |
| Pause/resume with changed settings | Imported 12 ordered videos; paused after the first four 8×8 JPEGs were saved; switched to 3×3 PNG while paused; resumed and saved the remaining eight PNGs. Final state: Saved 12 |
| Active cancellation | Started another 12-video batch, confirmed Stop while it was active; stopped after three new exports. Queue stayed available, completed files and preview remained, controls re-enabled |
| Previously exported files | Hashes of all five outputs from the initial mixed/manual run remained unchanged after later tests |
| Relaunch | Explicit English and Light selections persisted after quitting and reopening the isolated app |

The moving video fixtures are actual encoded media generated for testing, not
production footage. The H.264/HEVC fixtures were copied into the new directory;
the short and VFR fixtures were generated during this run. No third-party movie
or private user video was needed.

## Language and appearance checks

All seven languages were selected in the real packaged app, in the order
English → 中文 → Français → Русский → Español → 日本語 → 한국어. Arabic was absent.
The queue and saved result survived switches, and the saved-result status
translated immediately.

The main window was checked at its 940-point width. French, Russian, Spanish,
Japanese and Korean labels remained within their areas; longer Russian buttons
wrapped instead of overflowing. Inspector content remained scrollable where
height was limited. English and Chinese were also checked. Native macOS file
dialogs and OS-provided error messages follow the operating-system language;
they are not controlled by the app's language picker.

System appearance was exercised under the host's light appearance. Switching
to Dark and then Light restored both text and surface colors. The Korean manual
editor was also checked in Dark; English manual editing was exercised in Light.
This run did not visually check every manual-editor language at its minimum
window size or change the global macOS appearance to test system-mode transitions.

## Open defect: P2 — non-video file is incorrectly sent to conversion help

**Reproduction**

1. Create a disposable `invalid.mp4` containing the UTF-8 text
   `invalid media fixture, not a video` (34 bytes, no MP4 container).
2. Add it to ShotMap, optionally followed by valid videos, and generate.
3. Open Failure details.

**Actual:** the row shows “Conversion needed” and “This Mac cannot read the video
format. Convert it to MP4 or MOV using H.264 or H.265.” A Conversion help action
is offered.

**Expected:** classify this demonstrably non-video input as unreadable/invalid
media and advise checking or replacing the source. Conversion guidance is useful
for an otherwise valid video with an unsupported codec, not for this text file.

**Impact:** misleading recovery instructions; the file is rejected safely and
subsequent valid jobs still complete. This is not a crash or data-loss defect.

**Confirmed cause:** `VideoStoryboardAnalyzer.analyze` maps every `!isPlayable`
asset to `StoryboardError.unsupportedCodec` before checking duration or tracks.
The later failure classifier consequently offers conversion help. A fix should
distinguish invalid containers/no usable video data from genuine unsupported
codecs rather than reversing the blanket classification for every unplayable
asset. The finding is limited to this reproducible input; it does not establish
the diagnosis for every kind of damaged video.

No production fix was made as part of this independent test pass.

## Additional release-channel checks by the coordinating agent

These checks were supplied separately by the coordinating agent during this run:

- GitHub latest stable release is v0.2.15; the main-branch Verify run
  [40183784456](https://github.com/ixiehao/ShotMap/actions/runs/40183784456) passed.
- Anonymous public downloads of the DMG and checksum verified successfully and
  matched the local artifact byte-for-byte: 16,060,143 bytes; SHA-256
  `7c243506a81e8009ea56a96e9d5523990c0af31ac4badd2eeac9c69d33267f94`.
- `verify_public_project.py` passed. All 17 local links/images in each of the
  three READMEs exist; download links target the correct latest release.
- Public release notes use English, Chinese, Japanese and Korean in that order.

## Evidence and remaining limits

Local evidence directory: `/tmp/ShotMap-ReleaseQA-20261025.jU6BnN/`.

- `swift-test.log`: this run's XCTest output.
- `output-verification.json`: hashes, dimensions and format of all 21 exports.
- `outputs-after-manual.json`: hashes used to check earlier output preservation.
- `paused-outputs.txt`: the four files present at the pause boundary.
- `screenshots/fr-main.png`, `screenshots/ru-main.png`,
  `screenshots/cancelled-batch.png`: selected UI evidence.
- `media/`, `readonly/`, `batch/`: fixtures and generated results.
- Coordinator evidence: `/tmp/shotmap-postrelease-audit-20261025/`.

Not covered in this run: Intel or macOS 13 runtime, a fresh Mac's downloaded-app
Gatekeeper/first-install behavior, native-speaker review of every string,
long-form real HEVC/VFR footage, codec stalls, disk-full/network-volume removal,
screen-reader/keyboard-only operation, multi-hour stress/energy measurements,
or every possible media format. Synthetic integration tests and ad-hoc signature
validation do not prove those cases. Physical Finder drag/drop was not repeated;
the actual item-provider callback and ordering tests did run in XCTest.

## Source-fix follow-up — 2026-10-26

The analyzer now validates duration before checking playback support. Metadata
parse errors reach the existing failure classifier instead of being replaced
with an unsupported-codec error. An unplayable asset must also contain a video
track before conversion advice is offered. Playable inputs do not incur an
additional track-loading request.

Two regression tests were added:

- A real batch containing the original 34-byte text fixture, an empty MP4, a
  truncated MOV, and a valid generated H.264 movie. Before the fix, all three
  invalid inputs incorrectly received conversion advice. After the fix, they
  receive the existing localized unreadable-video message, and the final valid
  movie still exports a decodable 1920-pixel-wide image.
- A generated MOV with its video sample-description codec changed to an unknown
  tag. Its duration and video track remain readable, and it still receives
  conversion advice in all seven languages. This checks the unsupported-codec
  path without requiring a third-party codec or private fixture.

Both focused tests passed after the fix. The complete suite passed with
**129 tests, zero failures** (32.755 seconds). Public-project and whitespace
checks also passed. The universal release build passed with complete concurrency
checking and warnings-as-errors. The toolchain emitted its existing x86_64
deprecation warning; inspecting the resulting Mach-O confirmed both `arm64`
and `x86_64` still declare macOS 13.0 as their minimum. Logs are in
`/tmp/shotmap-invalid-media-release-build.log`,
`/tmp/shotmap-invalid-media-before.log`,
`/tmp/shotmap-invalid-media-after.log`, and
`/tmp/shotmap-invalid-media-full-tests.log`.

This follow-up describes the source fix; it does not change the previously
published v0.2.15 DMG or replace the original independent GUI test record.
The fix is included in the v0.2.16 / build 26 release source.
