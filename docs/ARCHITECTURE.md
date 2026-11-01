# Architecture

ShotMap is a native macOS storyboard generator. Its deliberately small
architecture uses only Apple system frameworks: SwiftUI, AVFoundation, Vision,
CoreGraphics, ImageIO, and AppKit. There are no package dependencies,
media sidecars, bundled ML models, analytics SDKs, or runtime asset downloads.

## Privacy boundary

The selected video stays on the Mac. AVFoundation decodes it locally and Vision
runs its face and human-rectangle requests on-device. Generated images are saved
beside the source video or through Save As. Failed exports use temporary local
preview storage so users can retry without retaining full batches in memory.
ShotMap has no account, media upload path, or internal media library. The update
checker requests only public GitHub release metadata. See [PRIVACY.md](../PRIVACY.md).

## Processing pipeline

The UI and processing code have separate ownership:

| File | Responsibility |
| --- | --- |
| `ContentView.swift` | Main workspace layout and user commands |
| `AppPreferencesCommands.swift` | Native View-menu appearance/language choices using existing preferences |
| `StoryboardCanvas.swift`, `PreviewCanvasLayout.swift` | Whole-image fit without user zoom or cropping |
| `PreviewWindowAutoFit.swift` | Completed-result aspect-based native window sizing with screen bounds and stable result identity |
| `StoryboardCanvasImageLoader.swift` | One current result's bounded, background high-resolution display image |
| `StoryboardViewModel.swift` | Batch state, result navigation, and run-checked UI updates |
| `ManualFrameEditor.swift` | Manual selection, player controls, and editor task lifetime |
| `ManualEditorTimeline.swift` | Bounded timeline positioning and frame stepping |
| `ManualVideoPlayback.swift` | Playback, bounded time observation, and player teardown |
| `OrderedVideoDrops.swift` | Ordered batches of asynchronous file providers |
| `FrameThumbnail.swift` | Serialized background thumbnail decoding and view-owned image lifetime |
| `ManualFrameEditorWindow.swift` | AppKit window ownership and SwiftUI presentation |
| `ManualFrameEditorRequest.swift` | Stable identity and settings for an editing session |
| `VideoQueueViews.swift`, `StoryboardPreviewViews.swift` | Queue and preview presentation |
| `StudioControls.swift`, `ManualEditorControls.swift`, `StudioLayout.swift` | Shared controls and fixed layout measurements |
| `BatchSupportViews.swift` | Failure reports and conversion guidance |
| `VideoStoryboardAnalyzer.swift`, `ManualFrameExtractor.swift` | Automatic analysis and exact manual capture |
| `AutomaticFramePipeline.swift`, `AutomaticFrameSamplingPolicy.swift` | Audited automatic candidates, shared recovery budgets and exact output |
| `AutomaticVisionCancellation.swift` | Thread-safe registration and cancellation of active Vision requests |
| `FrameQualityAnalyzer.swift` | Active-area quality, subject clarity and dense-text risk |
| `FrameSelection.swift` | Deterministic scene, quality, and diversity selection |
| `StoryboardComposer.swift`, `ImageCodec.swift` | Bitmap layout, encoding, and display thumbnails |
| `StoryboardPreview.swift`, `BatchRunControl.swift` | Serialized output, temporary previews, pause and cancellation |

The preview-first workspace uses compact, collapsible queue and inspector panels.
Focus mode restores the previous panel combination; generation remains in the
global toolbar. Appearance and language live in the native View menu, sharing
the existing settings rather than migrating preferences. See
[the workspace design and acceptance record](WORKSPACE-REDESIGN.md).

The completed-result canvas keeps the full image visible, without a zoom toolbar
or gesture magnification. On completion and result/panel changes, a native
window fitter uses the measured canvas and the complete image aspect ratio to
reduce unused space. It stays inside the current screen, respects minimum
control sizes and skips fullscreen and live window resizing. A global bottom
bar places file actions left, result navigation at the window centre and
manual frame selection in a prominent blue button on the right.
For a saved result it may decode one display image up to 2560 px off MainActor,
retaining at most 32 MiB of additional pixel storage. This excludes ImageIO
temporary buffers and system rendering allocations. URL, original preview-image
identity and request ID reject stale completions. Display upgrades preserve the
logical document size and whole-image fit; missing files retain the
original preview. The extra image is released when the canvas closes or changes
results, and is not a decoded batch-history cache.

Views use shared layout constants and theme-aware surfaces. Processing
workers do not own windows; editor tasks and their detached workers are cancelled
together when superseded or closed. Timeline actions update the same position
used by the next action, so repeated frame stepping accumulates correctly.
Manual gallery cells reuse display-sized thumbnails instead of decoding JPEGs
inside SwiftUI body evaluation. Thumbnail dimensions account for display scale,
portrait images, and aspect-fill cropping; a single decoder actor bounds work.
Cells release decoded images when they leave the screen, and a completed batch
releases the individual live-grid images after showing the finished storyboard.
File-provider callbacks collect into ordered batches before publishing queue
changes. Consecutive drops retain their arrival order; stalled providers time
out after 30 seconds, and cancellation invalidates late callbacks. The editor
player publishes its position at 10 Hz and removes its observers and current
item when closed. Adding a frame during playback pauses at the actual player
position before starting exact capture.

The manual editor uses a theme-aware neutral AVPlayerLayer surface. Playback
moves to the timeline toolbar, leaving the full monitor height for the video.
Portrait candidate galleries use five columns at the 1000 pt minimum window
width and six at the normal 1280 pt width. Cancel and Apply share the top toolbar;
there is no gallery title row or bottom action bar. Selected cards use a 36 pt
numbered badge, a 3 pt blue border and a 1 pt white inner keyline.

Fresh export defaults are 3×3, source aspect ratio, 1920 px, ivory background,
timestamps enabled, filename title disabled, and JPEG. View-model and export
settings defaults are checked together to prevent UI/export divergence.

```text
video URL
  -> one AVFoundation batch decodes an aspect-preserving coarse candidate set
  -> FrameQualityAnalyzer checks active-area blankness and multi-scale clarity
  -> terminal candidates receive explicit face/body/text observations
  -> bounded local and distributed recovery fills quality/content gaps
  -> FrameSelection ranks only eligible candidates and preserves timeline order
  -> same-size audited raw images are reused; size upgrades decode exact PTS
  -> the final quality gate rejects failed or unreviewed substitutions
  -> audited frames stream into stable live-grid slots and StoryboardComposer
```

`AutomaticFramePipeline` owns the automatic run. `AutomaticFrameSamplingPolicy`
shares an additional request budget across recovery and detailed text review.
A 64 MiB analysis-image cache bounds retained bitmaps; compact JPEGs are used
only when needed for previews or cache eviction. A resident original CGImage at
the audited PTS and sufficient requested size can enter the same final verifier
without another seek. A compressed preview is not treated as the original.
`FrameQualityAnalyzer` uses
Accelerate/vImage and vDSP for small grayscale planes; Vision retains automatic
system device selection. There is no bundled ML model or mandatory new OS API.
The pipeline reduces repeated decoding and reuses audited image evidence only
at matching timestamps and sufficient resolution. These changes do not imply a
guaranteed hardware-inference speedup. First-use system OCR model compilation
can still add latency; standalone warm-run timings do not predict cold GUI
response. The workspace exposes cancellation and progress while processing.

`ExportSettings` constrains the grid to the UI's 3 x 3 through 8 x 8 choices
and clamps exported width to at least 1920 px. Rendering uses CoreGraphics, so
the final image is composed in memory without an intermediate image editor.
Canvas allocation is capped at 64 megapixels and 16,384 pixels on either edge;
large portrait exports are scaled down before allocation to keep peak memory
reasonable on older Intel Macs. Rendering checks cooperative cancellation between
cards so a cancelled batch can stop before encoding an obsolete result.
All text rendered into exported images uses the bundled, unmodified Noto Sans
CJK SC Bold 2.004 font. The font is registered only for the app process; its
SIL Open Font License 1.1, source release, and checksum are retained in
[NOTICE.md](../NOTICE.md).

The automatic pipeline preserves each decoded source `CMTime` as rational
identity. Discovery requests may fall between source frames: their actual returned
PTS becomes the candidate identity and receives a fresh audit. Final-size and
detailed-text decodes must match an already audited PTS; they cannot silently move
to a nearby keyframe during a size upgrade. A rejected final image cannot recover from its
lower-resolution counterpart. Bounded audited alternatives may replace it;
insufficient valid output is an explicit error rather than duplicated filler.

Recovery reserves a distributed quota before filling local requests, so a large
set of weak local candidates cannot consume all coverage work. Coverage gaps are
computed from the entire export-verified pool, rather than just the K current
choices. Existing unreviewed representatives are audited before new seeking;
confirmed credit intervals and already attempted soft improvements do not cause
unconditional repeat searches. Request caps and final-frame gates still apply.
Credit evidence is propagated only within content-supported segments; an
intervening credible person scene or a sufficiently covered text-negative
observation interrupts propagation. An empty OCR result from a restricted region
is not evidence that the rest of the image has no text. If that region misses
uncertain text, a lightweight whole-image text-region and fast-recognition pass
can locate it in the same decoded image, followed by at most one additional
bounded accurate region. This does not add another image decode or an unbounded
full-page accurate OCR pass. Dense unreadable layouts remain uncertain.
OCR rectangles from a restricted region are mapped back into whole-image
coordinates before layout checks. Detected words are transient analysis evidence,
not included in application diagnostics.

The optional opening-overlay review has its own one-request allowance, charged
to the same recovery cap. A later trusted person scene, prior lower-left OCR
fragments and aligned pixel-row evidence schedule one exact high-size check.
An explicit, reliable film-funding sentence confirms exclusion. Weak layout
hints alone do not put all person-free candidates behind an unfinished OCR gate.

Subject readability is sampled from an original-image crop without upsampling
small subjects, and is used for soft ranking. Severe rejection thresholds remain
separate. Audited, at-least-as-readable alternatives may replace weaker crowded
frames even when they score below 70% of the film's best close-up. Diversity
repairs preserve quality and temporal spacing; static footage can still fill
the grid with distinct source timestamps when it lacks distinct compositions.

Developer profiling is enabled with `SHOTMAP_FRAME_PERFORMANCE=1`. Its decode,
quality, Vision, OCR, selection and encoding scopes include nested work; their
sum is not pipeline wall time. The normal profiling path avoids clocks, locks
and JSON output. These measurements contain counts and timings, not recognized
text or user media paths.

Task cancellation cancels the active generator and asks registered Vision
requests to cancel. Vision request registration is protected by a small lock;
framework calls run outside it. Cancellation propagates as `CancellationError`,
not a fabricated negative subject/text observation. This is best-effort framework
cancellation, not a hard latency guarantee for a running inference.

## Selection behavior

Eligibility is separate from ranking. Confirmed blank/title cards and strong
blur evidence cannot be offset by people, brightness or novelty bonuses. Each
terminal candidate keeps explicit `notEvaluated`, `observed`, or `failed`
evidence states. No-person observations remain valid for scenery and other
person-free footage; missing analysis does not masquerade as zero detections.

Coarse sampling discovers time regions, not every shot in a long film. Local
recovery and conservative corresponding-subject comparisons improve blurry or
person-free provisional moments. Face regions take clarity priority over large
body boxes that may contain sharp background. Ordinary subtitles and small
watermarks are distinct from central title/credit layouts. Detailed text analysis
is restricted to a small risk shortlist and shares the recovery budget.

The optional manual editor samples a bounded second candidate set only when it is
opened. Smart selection reuses the same visual metrics and duplicate rules, while
the user can override any individual choice. Candidate and smart-selection tasks
are cancelled when the editor closes. Each edit is tied to a stable preview ID so
switching between batch results cannot overwrite the wrong storyboard.
The exact-time batch request map uses the submitted `CMTime`, not a rounded
nominal frame number, so distinct VFR moments remain distinct. Shared requests
decode once and deliver the image to every requesting candidate. Adding one
frame submits the same seven sharpness probes asynchronously, followed by a
single final-size decode. Selection-changing controls are locked while Apply is
preparing an export, so the displayed selection matches the exported snapshot.

## Interface languages

The application supports English, Simplified Chinese, French, Russian, Spanish,
Japanese, and Korean. A saved language choice wins over the system preferences;
first launch matches the first supported preferred language and otherwise uses
English. Every locale has the same required resource keys and format arguments.
Views use semantic status values so switching language updates existing results
without restarting or discarding the queue. Help and the separate manual-editor
window receive the chosen locale explicitly. Timeline order is unchanged.

## Concurrency and compatibility

Generation, frame analysis, manual sampling, and bitmap composition run outside
the main actor. UI updates return through a run-ID-checked bridge; cancelling or
starting a new batch invalidates late updates from older work. Swift concurrency
is compiled in complete checking mode during release verification.

The package deployment target is macOS 13. Release builds contain both `arm64`
and `x86_64` slices and use only APIs available at that target. The automated
suite includes generated H.264, HEVC, and variable-frame-rate portrait fixtures
covering decode, selection, composition, JPEG export, and manual refinement.
Codec fixtures check that returned timestamps identify real source frames.
Storage tests cover cancelled writes, invalid image data, temporary previews,
large histories, and cancellation of one paused worker without resuming others.
If a stored preview can no longer load, navigation restores the last successfully
displayed record by stable ID, keeping the image, filename, and edit target
consistent. A stale or cancelled load cannot replace a newer successful result.

## Known limits

- This is heuristic selection, not semantic understanding: it cannot promise
  the most dramatic, beautiful, or narratively important image.
- Very dark films, rapid edits, fades, animation, and footage with deliberate
  motion blur can make shot detection or quality scoring less reliable.
- Vision's face/person detection can miss subjects because of angle, scale,
  occlusion, costume, or lighting; it is a preference rather than a guarantee.
- Frame support and decode performance are determined by the codecs available
  in the user's macOS installation. Long or high-resolution videos can take
  time, though sampling is capped to keep work bounded.
- The default layout preserves the source video's aspect ratio. 16:9, 4:3,
  1:1, 3:4, 9:16, and 21:9 layouts are also available; every tile is still
  aspect-filled and may crop at its edges.

## Contributor notes

- Preserve the no-dependency, local-media design. Discuss any new entitlement,
  package, model, telemetry, or remote request before adding it.
- Keep video access scoped to a user-selected URL and keep derived media
  ephemeral unless the user explicitly exports it.
- Changes to selection thresholds should include deterministic unit tests for
  scene separation, duplicate rejection, and fallback behavior.
- Keep exported images at or above 1920 px wide and test all grid sizes from
  3 x 3 to 8 x 8.
- Keep batch processing sequential. Parallel video decoding can make the UI less
  responsive and increases memory pressure without helping a single video finish.
- If privacy-relevant behavior changes, update both this document and
  [PRIVACY.md](../PRIVACY.md) in the same change.
