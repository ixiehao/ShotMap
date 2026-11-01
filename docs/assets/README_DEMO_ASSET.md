# Public visual assets

Captured on 1 November 2026 from the packaged **ShotMap 0.2.17 (27)** app.
The interface and exported images are real application output. Each saved
capture was checked for complete window bounds, display scaling, cropping,
language, and the current logo before creating public derivatives.

## Demonstration footage

- Film: *Tears of Steel* (2012)
- Credit: © Blender Foundation / Blender Institute
- License: [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)
- Project: [Tears of Steel](https://mango.blender.org/)
- Original: [Blender's 720p download](https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov)

The original film and audio are not included in the repository or app.
Public screenshots, storyboard images, and the documentation GIF contain
reduced derivatives of this film. Selection, layout into storyboard tiles,
scaling, and encoding are the relevant changes to the film imagery.

## Screenshots and exports

- `website/assets/workspace-{en,zh,fr,ru,es,ja,ko}.webp`: complete main
  workspaces in all seven interface languages, used by the matching website
  page and README. These demonstrate the result after manual frame refinement.
- `website/assets/manual-{en,zh,fr,ru,es,ja,ko}.webp`: complete manual editors
  with a live video preview, timeline selection markers, nine selected frames,
  and a badge identifying a manually added frame.
- `readme-workspace-*.png`: PNG reference copies of those main captures.
- `website/assets/tears-of-steel-storyboard.webp`: a direct 3 × 3 JPG export,
  reduced proportionally for the website. Its 1,920 px original was saved by
  ShotMap with timestamps and the warm ivory background.
- `website/assets/workspace-dark-en.webp`: a separate real dark-mode capture.
- `website/assets/app-launch-screen.webp`: the empty workspace.
- `website/assets/video-to-storyboard-overview.webp` and
  `video-to-storyboard-overview.png`: preview focus mode with the panels hidden.
- `website/assets/workflow-ja.webp`: the Japanese manual editor reference.
- `website/assets/about-en.webp`: the packaged app's About panel and version.

`video-to-storyboard-demo.gif` is a **condensed sequence of real captured
operation states**, rather than a continuous screen recording. It shows the
storyboard, manual frame choices, timeline markers, and the saved result.
Every full window fits the 960 × 622 canvas. The PNG fallback shows the manual
editor. Website screenshots are compressed WebP files, around 140–240 KB.

[`demo-assets.json`](demo-assets.json) records dimensions, file sizes, source
and output checksums, footage attribution, app version, and processing.
The website logo is available as
[`brand-mark.svg`](../../website/assets/brand-mark.svg). No old logo is
painted over the new screenshots.

Rebuild derivatives from the verified private captures on a development Mac
with Pillow installed:

```sh
python3 scripts/build_demo_assets.py /path/to/captures /path/to/ShotMap-export.jpg
```

## Social preview

`social-preview.jpg` and `social-preview-v2.jpg` are the same canonical
1280 × 640 card. The featured image is a complete, real preview-focus window;
surrounding text and brand artwork are project graphics. The website keeps a
copy in `website/assets/social-preview.jpg`.

```sh
swift scripts/create_social_preview.swift /path/to/captures/preview-focus-en.jpg docs/assets/social-preview.jpg docs/assets/social-preview-v2.jpg
cp docs/assets/social-preview.jpg website/assets/social-preview.jpg
```

The card includes film attribution and is below GitHub's 1 MB limit.
Uploading it through the repository's **Settings → General → Social preview**
is separate from committing the file or deploying GitHub Pages.

Project artwork is available under the [MIT License](../../LICENSE).
The film derivatives retain the CC BY 3.0 credit and license above.
