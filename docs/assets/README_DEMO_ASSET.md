# Public visual assets

ShotMap’s public visuals now use real, current application captures—not
drawn or generated imitations of the product interface. They share one visual
system across the README files, the project website, release previews, and
installation guides.

## Approved demonstration footage

The screenshots show a silent, reduced derivative of footage recorded and
supplied by the project owner.

- Original filename: `船外机.mp4`
- Source dimensions and duration: 1920 × 1080, 129.033 seconds
- Source SHA-256:
  `beaddf7057f9c0f8c0f7f271373e4fdad17f1276a976f03dff098a36966f838c`
- Permission: the project owner authorised documentation use on 2026-09-17.
- Distribution: the original video and its audio are not committed. Only
  reduced screenshots and storyboard output are published.

## Product screenshots

- `readme-workspace-en.png`, `readme-workspace-zh.png`, and
  `readme-workspace-ja.png` are the screenshots used at the top of the three
  README files. Each shows the real Batch Studio in its matching interface
  language.
- `website/assets/workspace-en.webp`, `workspace-zh.webp`, and
  `workspace-ja.png` are the corresponding website hero captures.
- `website/assets/manual-en.webp` and `manual-zh.webp` are real manual-frame
  selection windows: player, visual timeline, frame stepping controls, and
  candidate gallery are all live product UI.
- `website/assets/workflow-ja.webp` is a Japanese workspace crop used so the
  Japanese website stays readable in Japanese as well.

`video-to-storyboard-demo.gif` and its PNG fallback are rebuilt from actual
workspace states. `video-to-storyboard-overview.png` is a real manual-frame
selection capture, not an illustrated stand-in. The GIF is kept at 960 × 540
for fast README loading.

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

## Localised installation guides

`install-guide-en.jpg`, `install-guide-zh.jpg`, and `install-guide-ja.jpg`
use localised copy and their matching real workspace capture for the first
launch card. The DMG card uses the real mounted installer image in
`install-screen-dmg.png`.

`install-guide-background.png` is a text-free original background reserved
for the guide renderer. It is deliberately separate from the DMG window
background, which has its own installation arrow and title.

```sh
swift scripts/create_install_guide.swift docs/assets/install-guide-background.png en \
  docs/assets/install-screen-dmg.png docs/assets/install-screen-launch.png \
  docs/assets/install-guide-en.jpg
```

Replace `en` and the locale-specific input/output assets with `zh` or `ja` to
refresh the other guides. All original project visual artwork is released
under the [MIT License](../../LICENSE); footage rights remain with its owner.
