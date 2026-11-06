# Product naming

Use the following names in all new user-facing copy, screenshots, installers,
and release notes. Keep the English name first when the three languages appear
together.

| Document language | Product name |
| --- | --- |
| English | `ShotMap` |
| 简体中文 | `视频一键拼图（ShotMap）` |
| 日本語 | `ShotMap（動画ワンクリック・モンタージュ）` |

## Project identifiers

Use the same project identity in source, packaging, and public links:

- Bundle identifier: `com.ixiehao.shotmap`
- Swift package, executable, and module: `ShotMap` / `ShotMapApp`
- Repository and releases: `ixiehao/ShotMap`
- Distributed application: `ShotMap.app`

## Releases and downloads

- Release title: `ShotMap v<version>`.
- Apple Silicon installer: `ShotMap-<version>-arm64.dmg`.
- Intel installer: `ShotMap-<version>-x86_64.dmg`.
- Each checksum uses the complete installer filename followed by `.sha256`.

GitHub asset labels must retain the complete filename, including the product
name, version, architecture and extension. For example:

```text
ShotMap-0.2.18-arm64.dmg (Apple Silicon)
ShotMap-0.2.18-arm64.dmg.sha256
ShotMap-0.2.18-x86_64.dmg (Intel)
ShotMap-0.2.18-x86_64.dmg.sha256
```

Never replace the filename with an architecture-only label such as
`Apple Silicon` or `Intel`. Leaving a label unset also lets GitHub display the
actual filename. A label correction should preserve the asset's filename,
download URL and checksum; it does not require a new app version or re-upload.

The [IINA](https://github.com/iina/iina/releases/latest) and
[LocalSend](https://github.com/localsend/localsend/releases/latest) release pages
are examples of displaying complete product/version filenames.
