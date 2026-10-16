# Public visual assets

ShotMap’s public visuals now use real, current application captures—not
drawn or generated imitations of the product interface. They share one visual
system across the README files, the project website, and release previews.

## Approved demonstration footage

The screenshots show reduced derivatives of the following openly licensed
film. The original video and its audio are not committed; only screenshots,
storyboards, and a short documentation GIF are published.

- Title: *Tears of Steel* (2012)
- Attribution: © Blender Foundation / Blender Institute
- Licence: [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)
- Project: [Tears of Steel — Blender Studio](https://mango.blender.org/)

## Product screenshots

- `readme-workspace-en.png`, `readme-workspace-zh.png`, and
  `readme-workspace-ja.png` are the screenshots used at the top of the three
  README files. Each shows the real Batch Studio in its matching interface
  language.
- `website/assets/workspace-en.webp`, `workspace-zh.webp`, and
  `workspace-ja.webp` are the corresponding website hero captures.
- `website/assets/manual-en.webp`, `manual-zh.webp`, and `manual-ja.webp`
  are real manual-frame selection windows: player, visual timeline, frame
  stepping controls, and candidate gallery are all live product UI.
- `website/assets/tears-of-steel-storyboard.webp` is a direct ShotMap export
  from the approved footage. It is kept separate from the surrounding
  application-window captures so the website shows each step without
  repeating the same image.

`video-to-storyboard-demo.gif` and its PNG fallback are rebuilt from actual
*Tears of Steel* workspace and manual-selection states.
`video-to-storyboard-overview.png` is a real manual-frame selection capture,
not an illustrated stand-in. The GIF is kept at 960 × 620 for fast README
loading.

The original ShotMap Iris icon is intentionally retained as the stable product
identity. Its canonical source is `Assets/AppIcon-1024-source.png`; the
in-app and website copies are derived from the shipped application icon.

## Social preview

`social-preview.jpg` and `social-preview-v2.jpg` are 1280 × 640 link-preview
cards. Their featured image is the real manual-frame-selection workspace.
The surrounding typography and background are original project artwork; no
product UI is simulated.

Regenerate the cards on macOS with:

```sh
swift scripts/create_social_preview.swift \
  website/assets/manual-en.webp \
  docs/assets/social-preview.jpg \
  docs/assets/social-preview-v2.jpg
```

All original project visual artwork is released under the [MIT License](../../LICENSE). The *Tears of Steel* derivatives are
published with the attribution and CC BY 3.0 licence notice above; the film
itself remains available from Blender Studio.
