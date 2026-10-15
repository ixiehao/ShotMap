# Product naming

Use the following names in all new user-facing copy, screenshots, installers,
and release notes. Keep the English name first when the three languages appear
together.

| Document language | Product name |
| --- | --- |
| English | `ShotMap` |
| 简体中文 | `视频一键拼图（ShotMap）` |
| 日本語 | `ShotMap（動画ワンクリック・モンタージュ）` |

## Compatibility identifiers

`ShotTessera` is a legacy technical identifier, not the product name. It is
intentionally retained during the transition in places where changing it would
break an existing installation or public link:

- GitHub repository and release URL: `ixiehao/ShotTessera`
- Bundle identifier: `com.shottessera.videoscreenshotcollage`
- Swift package, module, executable, update-check endpoint, and Homebrew cask
  identifier: `shottessera`

The distributed application is named `ShotMap.app`. A future repository or
cask move must provide redirects and an explicit migration path before these
compatibility identifiers are changed.
