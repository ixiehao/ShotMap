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
| `StoryboardViewModel.swift` | Batch state, result navigation, and run-checked UI updates |
| `ManualFrameEditor.swift` | Manual selection, player controls, and editor task lifetime |
| `ManualEditorTimeline.swift` | Bounded timeline positioning and frame stepping |
| `ManualFrameEditorWindow.swift` | AppKit window ownership and SwiftUI presentation |
| `ManualFrameEditorRequest.swift` | Stable identity and settings for an editing session |
| `VideoQueueViews.swift`, `StoryboardPreviewViews.swift` | Queue and preview presentation |
| `StudioControls.swift`, `ManualEditorControls.swift`, `StudioLayout.swift` | Shared controls and fixed layout measurements |
| `BatchSupportViews.swift` | Failure reports and conversion guidance |
| `VideoStoryboardAnalyzer.swift`, `ManualFrameExtractor.swift` | Automatic analysis and exact manual capture |
| `FrameSelection.swift` | Deterministic scene, quality, and diversity selection |
| `StoryboardComposer.swift`, `ImageCodec.swift` | Bitmap layout, encoding, and display thumbnails |
| `StoryboardPreview.swift`, `BatchRunControl.swift` | Serialized output, temporary previews, pause and cancellation |

Views keep the existing layout constants and appearance choices. Processing
workers do not own windows; editor tasks and their detached workers are cancelled
together when superseded or closed. Timeline actions update the same position
used by the next action, so repeated frame stepping accumulates correctly.

```text
video URL
  -> AVAssetImageGenerator samples a bounded set of frames
  -> each adaptive-size analysis image is retained as a compact JPEG; PixelMetrics
     makes a 48 x 48 luminance histogram, exposure/black score, edge-detail score,
     and perceptual fingerprint
  -> FrameSelection finds histogram-based shot ranges, ranks a representative
     from each range, supplements short-cut videos by time bucket, and removes
     near duplicates
  -> Vision scores only promising JPEG candidates for faces and full-body people
  -> selected JPEGs stream to stable live-grid slots; low-detail selections are
     refined and remaining small-grid selections receive a presentation-size decode
  -> StoryboardComposer lays out rounded cards using the chosen aspect ratio
  -> the shared ImageCodec uses ImageIO for background decode/encode and writes
     the requested PNG or JPEG
```

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

Selections returned by refinement are excluded from the presentation-upgrade
pass, preserving the existing priority of refinement results (including their
fallbacks) over presentation upgrades. Manual refinement encodes final images as they arrive,
retaining compressed JPEGs rather than an entire gallery of final-size bitmaps.
The diversity scorer keeps each candidate's minimum distance to the selected set
and updates it once per new selection, preserving its scoring and tie order.

## Selection behavior

Scene boundaries come from differences between compact luminance histograms.
Candidates are rejected or penalized when they are almost black, too dim,
low-detail (a blur proxy), or perceptually close to an already chosen image.
Face close-ups and large human rectangles receive an additional preference
score. When a video does not contain people or has too few detectable cuts,
the selector gracefully falls back to good, time-distributed visual frames. A
strict pass removes near duplicates; a final relaxed time-bucket pass is only
used to fill every requested cell on sparse, long-shot source material.

The optional manual editor samples a bounded second candidate set only when it is
opened. Smart selection reuses the same visual metrics and duplicate rules, while
the user can override any individual choice. Candidate and smart-selection tasks
are cancelled when the editor closes. Each edit is tied to a stable preview ID so
switching between batch results cannot overwrite the wrong storyboard.

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
