# ShotMap

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

![ShotMap's real English workspace creating a storyboard from Tears of Steel](docs/assets/readme-workspace-en.png?v=tears-20261016)

## See what is in a video—at a glance

**ShotMap** turns the representative moments in a video into one clear storyboard image. Browse the story before opening the file, then return to the original video only when you need it.

Smart Select gives you a useful starting point. If one moment is not right, the manual picker lets you replace it with the frame you want. Everything happens on your Mac.

> **Get ShotMap:** [latest universal DMG](https://github.com/ixiehao/ShotMap/releases/latest) · macOS 13 or later · Apple Silicon and Intel

> **Demo footage:** *Tears of Steel* (2012) © Blender Foundation / Blender Institute, licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). The screenshots and animation below use this footage.

## From video to storyboard in three steps

| 1. Add videos | 2. Choose the moments | 3. Save the storyboard |
| --- | --- | --- |
| Drop in one video or queue several. | Start with Smart Select, then adjust any frame yourself. | Export a PNG or JPG beside the original video. |

## Made for finding moments quickly

- Starts with clear, representative frames and avoids black, blurry, and near-duplicate shots.
- Lets you refine a result in the Manual Frame Editor: player, visual timeline, frame steps, and candidate gallery are all in one place.
- Processes a visible queue and fills the storyboard preview as each result is ready.
- Offers 3 × 3 through 8 × 8 grids, aspect ratio, background colour, image width, optional timecodes, and file titles.
- Supports MP4, MOV, MPEG, and other formats supported by macOS.
- Works in English, 简体中文, and 日本語, with Light, Dark, or System appearance.

### See the real workflow

This recording shows the real app moving from a completed storyboard to the Manual Frame Editor, where you can find a moment on the visual timeline and choose a better candidate before saving.

![ShotMap moves from its Tears of Steel storyboard workspace to the manual frame editor, showing the visual timeline and candidate gallery](docs/assets/video-to-storyboard-demo.gif?v=tears-20261016)

## Download and install

With [Homebrew](https://brew.sh/):

```sh
brew install --cask ixiehao/tap/shottessera
```

Or download the [latest universal DMG](https://github.com/ixiehao/ShotMap/releases/latest), open it, and drag **ShotMap.app** to **Applications**.

ShotMap is not Apple-notarized yet. If macOS asks you to confirm the developer, Control-click the app in Applications, choose **Open**, then choose **Open** again. You do not need to lower system-wide security settings.

## Private by design

Your videos stay on your Mac. ShotMap has no account, tracking, cloud upload, Electron, FFmpeg, or Python runtime. Its optional update check reads public GitHub release metadata only; it never sends video or usage data.

## Project and feedback

- Website: [ixiehao.github.io/ShotMap](https://ixiehao.github.io/ShotMap/)
- Source, downloads, and release notes: [github.com/ixiehao/ShotMap](https://github.com/ixiehao/ShotMap)
- Feedback and feature ideas: [open a GitHub issue](https://github.com/ixiehao/ShotMap/issues/new/choose)
- Developer: [ixiehao](https://github.com/ixiehao)
- What changed: [CHANGELOG.md](CHANGELOG.md) · Privacy promise: [PRIVACY.md](PRIVACY.md)

## Rights and license

- ShotMap’s Swift source, documentation, and Iris icon are original project work released under the [MIT License](LICENSE).
- The app uses Apple SDK frameworks only. It bundles no third-party application code, packages, analytics SDKs, or MoviePrint assets.
- The bundled [Tabler Icons Outline](https://github.com/tabler/tabler-icons) SVGs are used unmodified under the [MIT License](ThirdPartyLicenses/TablerIcons-MIT.txt). The bundled Noto Sans CJK font is licensed under the [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt). See [NOTICE.md](NOTICE.md) for details.
- Documentation demo footage is *Tears of Steel* (2012) © Blender Foundation / Blender Institute, used under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- Process only videos you own or are authorised to analyse. Creating a storyboard does not grant rights to publish or redistribute the source video.
