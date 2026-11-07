<p><img src="website/assets/app-icon.png?v=20261101-release017" width="72" height="72" alt="ShotMap" /></p>

# ShotMap

[![Latest release](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![Verify](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**App interface in 7 languages:** English · 简体中文 · Français · Русский · Español · 日本語 · 한국어. Included in both installers.

![ShotMap's real English workspace creating a storyboard from Tears of Steel](website/assets/workspace-en.webp?v=20261101-release017)

## Turn each video into one storyboard.

**ShotMap** is a free, open-source Mac app that brings scenes from a video together in one storyboard image. Browse family recordings, travel clips, or editing footage without opening every file and scrubbing through it.

Start with automatic frame selection, then replace or fine-tune any frame on the timeline. Add several videos to process in a batch and export PNG or JPG images beside the originals. Processing stays on your Mac, with no account or video upload.

> **Start here:** [Download the latest international edition](https://github.com/ixiehao/ShotMap/releases/latest) · Apple Silicon / Intel DMGs · macOS 13 or later · Apple Silicon and Intel

> **Demo footage:** *Tears of Steel* (2012) © Blender Foundation / Blender Institute, licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). The screenshots and animation below use this footage.

## For the moments you want to find again

- **Family and personal archives:** locate a birthday, trip, sunset, or first step without opening every file.
- **Creators and editors:** scan a batch of clips before bringing the right material into an editing timeline.
- **Organising a video folder:** save an easy-to-scan storyboard beside each original video, with optional timecodes and filenames.

## From video to storyboard in three steps

| 1. Add videos | 2. Choose the moments | 3. Save the storyboard |
| --- | --- | --- |
| Drop in one video or queue several. | Start with Smart Select, then adjust any frame yourself. | Export a PNG or JPG beside the original video. |

## Choose the frames and layout that work for you

- **Automatic selection to get you started:** prioritises clear, varied frames while aiming to reduce black, blurry, and near-duplicate shots.
- **The final choice is yours:** use the player, timeline, and frame steps to find a moment. Smart Select keeps your selected frames and fills the remaining slots.
- **Organise several videos at once:** batch processing, progress previews, and a pause after the current video help you work through a collection.
- **Images you can open and share:** export PNG or JPG, with optional filenames and timecodes to help you return to the source.
- **A layout that fits your footage:** choose 3 × 3 to 8 × 8 grids, aspect ratio, image width, and background colour.
- **Made for Mac:** a native app with seven interface languages and Light, Dark, or System appearance.

Supports MP4, MOV, MPEG, and other video formats supported by macOS.

### See the real workflow

This short demo shows the real app moving from a completed storyboard to the Manual Frame Editor, where you can find a moment on the visual timeline and choose a better candidate before saving.

![ShotMap moves from its Tears of Steel storyboard workspace to the manual frame editor, showing the visual timeline and candidate gallery](docs/assets/video-to-storyboard-demo.gif?v=20261101-release017)

## Download and install

Open the [latest release](https://github.com/ixiehao/ShotMap/releases/latest) and choose **arm64** for Apple Silicon (M-series) or **x86_64** for Intel. Open the `.dmg` and drag **ShotMap.app** to **Applications**. Both installers include all seven languages.

The release page includes a SHA-256 checksum for people who want to verify their download. ShotMap is not Apple-notarized yet. If macOS asks you to confirm the developer, Control-click the app in Applications, choose **Open**, then choose **Open** again. You do not need to lower system-wide security settings.

### Choose your language

Choose a language from the macOS menu bar to switch instantly, without restarting or clearing your queue. On first launch, ShotMap matches a supported system language or falls back to English; it remembers your choice after that.

## Private by design

Your videos stay on your Mac. ShotMap has no account, tracking, cloud upload, Electron, FFmpeg, or Python runtime. Its optional update check reads public GitHub release metadata only; it never sends video or usage data.

## Help, feedback, and community

- **New to ShotMap?** Visit the [website](https://ixiehao.github.io/ShotMap/) for a concise product tour and real screenshots.
- **Need help, found a bug, or have an idea?** Start with [Support](SUPPORT.md), then use an [issue form](https://github.com/ixiehao/ShotMap/issues/new/choose) for reproducible problems and focused feature requests.
- **Want to ask or share?** Join [GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions) for questions and workflow ideas.
- **Want to contribute?** Read [CONTRIBUTING.md](CONTRIBUTING.md). Security concerns belong in the private [security reporting flow](https://github.com/ixiehao/ShotMap/security/advisories/new).
- **Project details:** [CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [Developer: ixiehao](https://github.com/ixiehao)

## Rights and license

- ShotMap’s Swift source, documentation, and app icon are original project work released under the [MIT License](LICENSE).
- The app uses Apple SDK frameworks only. It bundles no third-party application code, packages, analytics SDKs, or MoviePrint assets.
- The bundled [Tabler Icons Outline](https://github.com/tabler/tabler-icons) SVGs are used unmodified under the [MIT License](ThirdPartyLicenses/TablerIcons-MIT.txt). The bundled Noto Sans CJK font is licensed under the [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt). See [NOTICE.md](NOTICE.md) for details.
- Documentation demo footage is *Tears of Steel* (2012) © Blender Foundation / Blender Institute, used under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- Process only videos you own or are authorised to analyse. Creating a storyboard does not grant rights to publish or redistribute the source video.

## Development documentation

[Documentation index](docs/README.md) · [Development and validation](docs/DEVELOPMENT.md) · [Website maintenance](docs/WEBSITE.md).

The official website source lives in `website/`; `docs/` is reserved for maintainer documentation.
