# Preview-first workspace

31 October 2026. This is an implementation record for the desktop workspace;
actual packaged-app observations are recorded separately during acceptance.

## Design basis

The primary task is to inspect a finished storyboard. The queue identifies the
inputs, the inspector changes the output, and neither should compete with the
picture. Apple’s [layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout),
[sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars)
and [toolbar guidance](https://developer.apple.com/design/human-interface-guidelines/toolbars)
support a clear content hierarchy and controls associated with their content.
The official [Final Cut Pro workspace guide](https://support.apple.com/guide/final-cut-pro/change-the-workspace-layout-ver6b3626147/mac)
provides a useful mature example: browser, viewer and inspector have separate
roles, and auxiliary regions can be hidden to give the viewer more room.
ShotMap adopts those principles, without adding a timeline or editing concepts
unrelated to generating storyboards.

The revised canvas always shows the complete exported image. The Fit/zoom row
and interactive magnification are removed. A native window-size controller uses
the measured canvas viewport and image aspect, keeping a preferred landscape
width or portrait height while adjusting the other dimension. This runs for a
new completed result or an explicit panel change, not during generation,
loading, fullscreen or a live user resize. Screen bounds and minimum control
sizes take precedence; some space can remain for extreme ratios or small screens.

The current saved result can supply a background-decoded display image up to
2,560 px, capped at 32 MiB of retained pixel storage. The default 1,920 px export
is not upsampled. One serial decoder and current-request identity prevent a
batch-history bitmap cache or stale-image replacement. Upgrading the backing
does not alter the original logical document size, whole-image fit. Missing/unreadable exports keep the existing preview. The byte cap
does not describe ImageIO's transient buffers or system rendering allocations.

## Layout and measurements

All dimensions below are logical points. Thin workspace separators use one
physical pixel at the current display scale, rather than assuming every screen
is Retina.

| Element | Measurement / behavior |
| --- | --- |
| Main toolbar | 48 pt; brand, queue/inspector toggles, focus action, generation |
| Queue | 190 pt; rounded cards with 26×30 pt numeric badges, two-line filenames and status |
| Inspector | 216 pt |
| Preview header | 40 pt; title and current status |
| Global bottom bar | 48 pt; local-processing caption left, centred 152×36 pt page control, blue manual selection right |
| Canvas | Remaining flexible space; full image fitted without cropping |
| Focus preview | Hides both side panels; restoring recalls the previous panel combination |
| Setting controls | 30 pt high; 11–12 pt text; all six grid choices retained |
| Main title | 15 pt; panel headings 12 pt; secondary text 11 pt |

The initial content area is 840 × 680, clamped to the available screen. The
first attachment applies this compact size once, including when macOS has
restored an oversized empty window. The empty state keeps its icon and title;
the explanatory subtitle is removed. After a completed result appears, the window
adapts to the full image's aspect using actual measured window chrome, rather
than a hard-coded title-bar estimate. Landscape results use a wider, shorter
window (1,280 pt preferred width); portrait results use a narrower, taller
window. A width manually chosen before the first result is respected. The minimum content
size is 720 × 480 with both panels visible, 600 × 480 with one, and 480 × 480
with neither. The compact toolbar retains the logo and actions, and drops only
the brand word below 650 pt. All inspector settings remain in a native scroll
view when the landscape window is short. A manually resized window is not
continually forced back on every layout or appearance update.

Completed-image navigation and actions sit outside the picture, so they do not
cover exported content or corners. Output aspect, composition, image size and
export defaults are not changed by window sizing.

## Controls and language

Appearance and language move to native single-selection submenus in the macOS
View menu, using the existing persisted settings. The controls are removed from
the window, while the language and appearance environment propagation remains.
The [menu-bar HIG](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
and [SwiftUI menu-bar guide](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui)
are the implementation references.

Generation stays in the global toolbar, including when settings are hidden.
Per-result navigation, showing the saved file, exporting an unsaved result, and
manual frame selection retain their existing model actions. Progress, pause,
resume, stop, failure details and retry remain available during the appropriate
batch states. Hiding a panel changes presentation only; it does not cancel a
job, clear the queue or alter export settings.

The compact inspector uses a separate label row for the background swatches,
which avoids long English/Russian labels forcing the row beyond its bounds.
Six background choices, their light-to-dark order, aspect, width, timestamp and
filename switches, PNG/JPEG choices and the existing default preset remain.
Important secondary text can wrap instead of being hidden by a fixed height.
All added labels have the same meaning in the seven supported languages.

## Queue and secondary information

Queue rows use a single, legible numeric badge in place of a decorative movie
icon. The number appears once, beside the two-line filename and explicit
Queued / Processing / Saved / Failed state. Processing has a light accent tint;
failed jobs a quiet red tint. The clear action remains a small destructive action.
A native scroll view, stable identities and the zero-copy indexed collection
remain in use for large queues.

The local-processing privacy caption is a secondary 10 pt line at the left of
the global footer, including the empty state. It does not occupy the queue.
The top toolbar keeps only the brand and workspace actions. Saved-result status
and the Finder/export action align to the right of the preview header; the
filename can truncate in the middle without displacing the preview title.

The top toolbar generation area uses the same 216 pt width as the inspector;
its separator shares the exact lower pane boundary. Hiding the inspector
removes that separator while retaining generation.

The footer page control has a shared 152×36 pt surface, larger 17 pt arrows,
a bold 15 pt current page and a quieter total. Available arrows receive a blue
tint; unavailable directions remain visibly disabled. Equal side columns keep
the control centred in the entire window.

## Manual frame editor

The editor shares `StudioPalette` with the main window: neutral cool surfaces,
blue emphasis, 8 pt control corners and display-scale-aligned dividers. Its
native title is the source filename and stays that way when language changes.

A large monitor and timeline share the top row. The media region is 298-320 pt
high according to window height. The preview's lower playback/status bar is
removed: the video uses the whole monitor, and playback moves to the timeline
header. Current position is entered once in a content-sized time field with
8 pt internal horizontal padding. Its width is measured using the actual 18 pt
monospaced font and source duration, so the complete timestamp fits without
stretching into unused space. Longer hour fields remain supported. The ruler
retains the source start/end times.

One 36 pt toolbar groups playback, the blue 28 pt selection fraction, Smart
select and New frames on the left, with Cancel and the solid-blue Save action
on the right. All action controls are 30 pt high. The selection group reserves
its measured maximum width, including an over-limit count after reducing the
grid. Actual AppKit font measurements cover all seven languages and the 64-frame
limit; a two-row fallback is available only when this measured group cannot fit.
The redundant timeline heading and bottom selection group are removed.

The Add frame button is a 26 pt floating overlay beneath the scrubber and follows
its playhead, clamped between the start/end timestamps so it cannot cover them.
It occupies no extra layout row: the local navigation box is 46 pt high and the
button starts at y = 20 pt. A fine separator introduces the centred frame-step
controls and time field below. Every action keeps a text label, independent of
video orientation.
Seven language bundles provide concise visible labels and retain the full
original descriptions in help/accessibility labels. Decorative layers/check/
smart/refresh icons are removed from these controls; the functional play/pause
icon remains. Frame-step buttons are 44 pt wide.

Frame-step values use 12 pt semibold monospaced type. Their localized units
use 9 pt secondary text on the same first baseline, with a 2 pt gap. The
44×30 pt click targets retain the full original accessibility labels;
visual units come from an explicit localization key rather than parsing a
translated phrase. This keeps longer Russian and Korean units quiet and legible
in both appearances.

A 24 pt marker lane above the filmstrip shows the selected frames' chronological
numbers only when frames are selected. An empty selection uses no marker-lane
height. The filmstrip gains that same space, so the outer media region, scrubber
and gallery stay in place when the first marker appears. Single pins seek to the original selected timestamp; crowded pins
share a numbered-range badge that opens a compact list of exact timestamps.
Every selected frame retains its own connecting stem. Badge heads are laid
out in non-overlapping slots, without moving the underlying time positions.
The same geometry maps selected pins, the playhead and the scrubber, including
both video endpoints. Selecting or deselecting a frame immediately updates both
gallery and timeline numbering. The lane fits inside the existing workspace;
the floating insertion button and single command row recover height for the
filmstrip, without increasing the workspace height or reducing the gallery.

The gallery starts immediately below the media workspace, without a separate
top or gallery toolbar. At 1000/1280 pt widths it retains three/four landscape
columns and five/six portrait columns. Complete portrait rows fit at the
supported minimum, verified by layout tests. Source frames remain fitted
without new cropping. Playback, scrubbing, time entry, stepping, smart
selection, regeneration, manual additions, ordered selection, apply/save and
cancellation retain their original handlers and cancellation lifetime.

Manually added candidates carry a persistent amber Manual badge at the upper
right, separate from the blue numbered selection badge at the upper left.
The origin label is localized in all seven languages and included in the
candidate's accessibility description. A completed insertion scrolls the
gallery to that frame; requesting an existing timestamp reveals its existing
candidate instead of creating a duplicate. The marker is editor-only and does
not modify or watermark exported images. Refreshing sampled candidates retains
the manually added array and its origin badges.

Smart select is now an additive fill. A snapshot of the current selection is
preserved, selected IDs are excluded from the scoring pool, and only the
remaining slot count is requested. Completion admits unique IDs from that pool
up to the available capacity and unions them with the preserved selection.
Three selected frames in a 3×3 grid therefore request six additional frames;
a full grid disables Smart select. Existing cancellation/token guards remain
in place. New frames remains the explicit action that clears the selection.

Manual Save takes one snapshot of the current Storyboard Settings at click
time. Grid, aspect, width, background, timecode, title, format and language use
that snapshot throughout refinement, composition and export. The old result
supplies its history identity, not its old export settings. Changing the grid
while editing updates the required count; increasing capacity appends distinct
candidates without changing existing candidate IDs, timestamps or manual origin.
Reducing the grid keeps selections and disables Save until the count matches.
Changing the same result's explicit layout aspect triggers window fitting;
pixel-resolution upgrades and appearance changes still do not.

## Visual system

Use system fonts and the existing Tabler Icons Outline library. Light appearance
pairs near-white panels with a neutral gray canvas; dark appearance pairs muted
panels with a darker neutral canvas. Blue identifies active controls, rather
than coloring every heading. Existing export backgrounds belong to the output
and are independent of these workspace surfaces.

## Acceptance requirements

- Generate and save a real landscape storyboard, inspect its full corners, use
  result navigation, open the manual editor, and return without losing the
  current queue or result.
- Inspect real landscape and portrait results, minimum sizes and focus mode.
  The whole picture must fit, the window must adapt, and changing language or
  loading higher-resolution display pixels must not repeatedly resize it.
- Verify independent panel toggles, focus restoration from different combinations,
  and generation while the inspector is hidden.
- Change appearance dark → light and switch languages from the native menu;
  check selection marks, existing result, queue, settings and menu labels.
- Cover long labels, multiple completed results, live generation, pause/resume,
  stop, import cancellation, failed-job details and retry without overflow.
- Run project tests and the strict universal build. Frame extraction, ranking,
  image composition and export defaults are outside this UI change.

Passing unit tests or computing a larger layout budget is not a substitute for
these packaged-app visual and interaction checks.

## Previous iteration: packaged-app acceptance

The observations below concern the earlier zoom-enabled workspace build, not
the revised automatic-window build. New acceptance is recorded separately.

Checked on an M1 Pro running macOS 27.0.1. The independent local test app is
`dist/ShotMap-Workspace-Test.app`; its bundle identifier is separate from the
installed release and previous test apps. There was no release or version bump.

- All 205 project tests passed. After the final compact-header adjustment,
  all 16 menu, canvas, display-image and grid-glyph checks passed again.
- The final universal build passed complete concurrency checking and Swift
  warnings-as-errors. Both arm64 and x86_64 slices declare macOS 13.0. Older
  systems and Intel hardware were not separately run.
- A real H.264 film excerpt generated and saved a 3×3 JPEG. A two-video batch
  using same-source HEVC and constructed H.264 VFR derivatives also saved both
  outputs while the settings panel was hidden. Header previous/next controls
  navigated both results, and changing results restored Fit.
- Native zoom controls showed 1.25× and 1.5×, exposed a real horizontal scroll
  range, and native scrolling moved to its right edge. Fit restored the whole
  image. These UI observations supplement the native scroll-view regression;
  a physical trackpad pinch was not separately exercised.
- The default 1280×800 window and the system-tiled minimum content size were
  inspected. The latter screenshot is approximately 940×668 points including
  native title-bar space. English and Russian controls stayed inside their
  panels; the longer Russian queue heading uses two lines instead of ellipsis.
- Native menu changes were exercised in Chinese, English, Russian and Japanese.
  Dark-to-light text colours changed correctly, result/queue settings survived,
  and language/appearance persisted after restart. All seven language entries
  were present; resources for all seven passed the automated checks.
- Focus mode hid both panels and restored the prior combination, including the
  case where only the inspector had been visible. Generation remained available.
  The manual editor opened in Japanese and cancelled back to the saved result.

Local unmodified screenshots are retained under
`/tmp/ShotMap-Workspace-Redesign-20261031/`: `workspace-zh-light.png`,
`workspace-focus-zh.png` and `workspace-ru-min.png`. They show *Tears of Steel*
(2012), © Blender Foundation / Blender Institute,
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), using excerpts and
transcoded derivatives of the [official source](https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov).

The eight frozen frame-selection/backend files remained byte-identical throughout
this UI change. No new speed claim is made from these GUI observations. The
previously recorded first-use system OCR compilation wait remains a backend
limitation; this workspace refactor does not claim to resolve it. Pause/resume,
stop and failure recovery retain their model tests and UI paths, but were not
each exercised as a separate new GUI scenario in this round.

## Revised automatic-window build acceptance

The independent `dist/ShotMap-Adaptive-Preview-Test.app` uses its own bundle ID
and leaves the installed app, previous UI test app and release DMG untouched.
The existing 204 tests passed, followed by all eight new window-geometry tests.
The strict universal release build passed; both architectures still declare
macOS 13.0. No frame-selection/backend source changed in this revision.

Actual packaged-app checks on M1 Pro / macOS 27.0.1:

- A two-video batch (H.264 VFR and HEVC CFR derivatives of the credited film)
  generated and saved complete 3×3 JPEGs. The landscape window changed from
  1280×800 to about 1280×543, with the complete image visible and small margins.
- Selecting the existing 9:16 output option and generating again changed the
  window to about 846×880. This tests a portrait-shaped exported storyboard;
  the source remains the same landscape film excerpt. No output cropping or
  composition policy was changed by the UI work.
- Returning to the source aspect and generating again restored the wider,
  shorter landscape window. Previous-result navigation worked at the bottom centre. The manual-frame
  button opened the existing editor and cancelled back to the same queue and
  result. Fit, magnification controls and gesture zoom are absent.
- Native dark → light switching updated queue, canvas, labels and footer.
  English and Russian labels stayed within the portrait window. Russian focus
  mode narrowed to 480×880; restoring panels returned to the wider portrait
  window with the same two jobs and image.
- The short landscape inspector exposes native scrolling, so settings remain
  accessible even when its export section is below the current viewport.

Unmodified local screenshots are in
`/tmp/ShotMap-Adaptive-Preview-20261031/`: `landscape-light.jpg`,
`landscape-dark.jpg`, `portrait-light-en.jpg`, `portrait-light-zh.jpg` and
`portrait-ru-panels-restored.jpg` and `landscape-return-zh.jpg`. They depict the same *Tears of Steel*
(2012) material credited above, cropped only by the app's explicitly selected
output aspect. Fullscreen transitions and physical Intel/older-macOS hardware
were not separately exercised in this round; geometry tests cover screen limits,
negative-origin displays and native minimum sizes.

## Interface refinement: intermediate acceptance

The intermediate local bundle is `dist/ShotMap-Interface-Test.app`, version 0.2.16 (26),
with the independent identifier `com.ixiehao.shotmap.interfaceQA20261031`.
The final complete suite passed all 212 tests; after the final typography
changes, all 32 editor/lifecycle/canvas/window regression checks passed again.
The eight frozen frame-selection/backend files remain unchanged. The shared
development README was updated locally, outside this public repository.

Actual-app checks covered numbered queue cards, the privacy caption in the top
bar, previous/next paging, native title filenames, playback, cumulative stepping,
time entry, adding a current frame, renumbering after selecting an earlier
frame, smart selection, candidate regeneration, apply/save, cancellation and
light/dark changes. Two differently encoded landscape excerpts and a portrait
crop derivative of the same credited film generated successfully. The source
video itself was never overwritten.

The final alignment uses the inspector's shared width; the separator was
visually checked and hides with the inspector. The manual editor was checked
at its normal size and the system-tiled minimum: one complete portrait row
remained visible, with six/five columns respectively. Russian long controls
were checked in the compact layout; text fitting was subsequently tightened
on the actual button Text views. These checks are UI acceptance, not a new
frame-quality or performance benchmark.

Current unmodified screenshots and QA-only portrait media are retained in
`/tmp/ShotMap-Interface-Polish-20261031/`. The portrait source is a centre-cropped
H.264 derivative of the already credited Tears of Steel excerpt, not separate
third-party footage. Earlier files in that directory document intermediate
layouts; final screenshots are explicitly named with `reference-layout`.

## Previous manual editor acceptance — 2026-11-01

The combined local test bundle is `dist/ShotMap-Manual-Test.app`, version
0.2.16 (26), with identifier `com.ixiehao.shotmap.manualQA20261031`.
It contains the final floating insertion control, manual-origin badges,
clickable timeline markers and additive smart fill, as well as the main-window
refinements described above. The arm64/x86_64 release build passed complete
concurrency checking with compiler warnings treated as errors. Both Mach-O
slices retain macOS 13.0 minimum deployment and match the built code after
ad-hoc signing. The SDK's Intel-target deprecation diagnostic is a toolchain
warning; physical Intel hardware was not separately exercised.

All 48 final targeted tests passed, including seven-language coverage,
localized unit fitting, timeline mapping/clustering, insertion-position limits,
manual selection retention, window geometry and save/cancellation lifetime.
The earlier complete suite passed 212 tests before the final editor additions;
it was not rerun in full after these changes. The eight frozen extraction files
and stable 0.2.16 DMG remain byte-for-byte unchanged.

Actual-app acceptance used the credited Tears of Steel H.264/VFR excerpt:

- The preview has no lower status bar. Smart select / New frames are at the
  top right; Add frame floats under the scrubber and avoids the endpoint times.
- Adding at an edited 47.123-second position created a refined manual candidate,
  displayed its amber origin badge and scrolled to it. The original video was
  not modified. No exact-time claim is made for sharpness refinement itself.
- Three manually selected candidates, including that added frame, remained
  selected after smart fill produced nine total. A full selection disabled
  smart fill. Gallery and timeline numbers updated in chronological order.
- Clicking a single timeline pin sought to 14.375 seconds. Expanding a grouped
  pin and choosing its second entry sought to 5.083 seconds. The editable field
  and preview reported those same millisecond timestamps.
- Russian dark mode at the system-tiled minimum retained complete labels,
  legible small gray units, the manual origin badge and all commit controls.
  The narrow layout used the intended stacked commit fallback.
- Save applied all nine frames and returned to the main window reporting
  `action-h264-vfr-shot-004.jpg`. Chinese light mode was restored afterward.

Unmodified current screenshots are in `/tmp/ShotMap-Final-UIQA-20261031/`:
`manual-final-selected-and-origin-zh.jpg` and
`manual-final-minimum-dark-ru.jpg`. They depict the same CC BY 3.0 film credited
above. Portrait sizing and whole-frame fitting retain the earlier verified
geometry; the final additive-fill interaction above was exercised with the
landscape excerpt. No new extraction-speed or memory benchmark is claimed.

## Compact startup and current-settings acceptance — 2026-11-01

The refreshed local test bundle remains version 0.2.16 (26), with identifier
`com.ixiehao.shotmap.settingsQA20261101`. The final targeted suite passed 92 tests
with no failures. The arm64/x86_64 release build passed complete concurrency
checking with compiler warnings treated as errors. Both slices retain macOS
13.0 deployment. This is a local test package, with no version bump or release.

Raw screenshots and test/build logs are retained in
`dist/qa-evidence/manual-settings-2026-11-01/`:

- `startup-zh.jpg`: actual 840×680 pt startup, both side panels and the single
  empty-state title visible, with the explanatory subtitle removed.
- `generated-landscape.jpg`: the first completed image expands the window to
  1,280 pt width and shows the full landscape storyboard.
- `manual-empty.jpg`: the compact toolbar shows 0/16, Smart select, New frames,
  Cancel and Save; there is no empty marker lane or redundant title row.
- `manual-saved-current-settings.jpg`: after changing the settings on an old
  3×3 JPEG result, manual Save produced a 4×4 portrait PNG at 2,560×4,423 px,
  with the navy background, filename shown and tile timecodes hidden. The
  same history result refitted to the new portrait aspect.

These checks used the reusable 60-second excerpt of *Tears of Steel (2012)*,
© Blender Foundation / Blender Institute, CC BY 3.0. The original remains
unmodified in the user's video library. Tests additionally cover click-time
settings snapshots, changes during refinement, live grid changes, candidate
identity retention, history identity and seven-language layout geometry.
They are not a new frame-quality, speed or memory benchmark. The eight frozen
extraction files and stable release DMG are unchanged.

## Object-video regression fix — 2026-11-01

Real object-led videos exposed a gate/budget mismatch: ordinary two-line model
labels required mandatory HD OCR, while a 3×3 job allowed only two HD checks.
In one reproduction, all 93 candidates passed pixel quality, but 42 otherwise
audited candidates remained ineligible solely for that additional review.
Mandatory review now requires dense text layout or at least three substantial
text rows with a stronger observed score; confirmed credit context still
schedules neighbouring review. Blank, severe-blur, confirmed-card, failed-audit
and exact-PTS gates are retained. Initial semantic checks reserve timeline
coverage from the existing budget. Static fallback spreads distinct timestamps
after visually different alternatives are exhausted.

Before the first accepted preview, the header and live grid show the actual
scan/select/assemble stage rather than an unchanging zero-captured count.
Stage progress is monotonic through optional recovery.

The background picker is now one connected, equal-width six-chip strip with
pure white first. An inset blue outline and contrast-aware Tabler check identify
selection without changing chip size. Aspect, width, background, timecode and
filename labels share one 11 pt medium, primary-colour helper in both appearances.
The existing ivory export default is retained.

The subsequent alignment adjustment moves the six-chip strip to the right of
its label. Aspect, width and background share the exact same trailing-column
width and 30 pt control height. The width is capped at 128 pt and measured from
the longest localized label so all three rows remain aligned in the compact
216 pt inspector. This layout-only change was strictly rebuilt for arm64/x86_64
and visually checked in the actual compact Chinese window; the 245-test
generation-fix suite above predates this adjustment.

The final complete suite passed 245 tests. Three previously failing real
object videos generated nine distinct timestamps each; a complete credited
film also succeeded. Exact local media, raw UI captures, output images and
single-run timing logs are retained only in ignored `dist/qa-evidence/`.
These warm-process single runs do not establish cold-start or general speed
claims. The historical frozen-backend statements above apply to their earlier
iterations; this fix intentionally changes selection/risk policy.
