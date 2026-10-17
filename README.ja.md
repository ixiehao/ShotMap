# ShotMap

[![最新リリース](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![検証](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

![Tears of Steel を処理して絵コンテを作成する ShotMap の日本語ワークスペース](website/assets/workspace-ja.webp?v=20261017)

## 動画を、見つけやすく。

家族の記録、旅行、日々の動画。ファイル名やサムネイルだけでは、どの動画に見たい場面があるのか分かりにくいことがあります。**ShotMap** は動画の見どころを一枚の絵コンテにまとめるので、一本ずつ再生せずに場面を見比べて探せます。

まずスマート選択の候補を確認し、必要なコマは手動フレーム選択で置き換えられます。ShotMap は macOS ネイティブのオープンソースアプリです。動画の処理と画像の書き出しは Mac 上で行い、アカウントや動画のアップロードは不要です。

> **ここから始める：**[最新 Universal DMG をダウンロード](https://github.com/ixiehao/ShotMap/releases/latest) · macOS 13 以降 · Apple Silicon / Intel Mac 対応

> **デモ映像のクレジット：** *Tears of Steel*（2012）© Blender Foundation / Blender Institute、[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) ライセンス。以下の製品スクリーンショットとアニメーションにはこの映像を使用しています。

## もう一度見つけたい場面のために

- **家族や個人のアーカイブ：**一つずつ開かなくても、誕生日、旅行、夕日、子どもの成長の場面を探せます。
- **クリエイターと編集者：**編集ソフトに読み込む前に、まとめて素材を確認し、本当に必要なショットを見つけられます。
- **動画フォルダの整理：**各動画の横に見やすい絵コンテ画像を保存。必要ならタイムコードとファイル名も表示できます。

## 3 ステップで絵コンテを作成

| 1. 動画を追加 | 2. 場面を選ぶ | 3. 絵コンテを保存 |
| --- | --- | --- |
| 一つの動画をドラッグするか、複数の動画をキューに追加します。 | まずスマート選択を使い、必要なコマだけ手動で調整します。 | 元動画の横に PNG または JPG を書き出します。 |

## 場面もレイアウトも、自分で調整

- 鮮明で変化のある場面を優先し、黒画面、ぼやけ、ほぼ同じコマをできるだけ減らします。
- 手動フレーム選択では、プレーヤー、視覚的タイムライン、コマ送り、候補ギャラリーを一画面で使えます。
- 見えるキューで複数動画を処理し、完成したコマからプレビューへ順に表示します。
- 3 × 3 から 8 × 8 のグリッド、比率、背景色、画像の幅、タイムコード、ファイル名タイトルを選べます。
- MP4、MOV、MPEG など、現在の macOS が対応する動画形式を扱えます。
- English、简体中文、日本語に対応し、ライト、ダーク、システムの外観を選べます。

### 実際の操作を見る

実際のアプリで、完成した絵コンテから手動フレーム選択画面を開き、視覚的なタイムラインで場面を探して候補から一コマを選び、保存する流れです。

![Tears of Steel の絵コンテを表示する ShotMap ワークスペースから手動フレーム選択画面へ移り、視覚タイムラインと候補ギャラリーを表示する操作](docs/assets/video-to-storyboard-demo.gif?v=tears-20261016)

## ダウンロードとインストール

**ほとんどの方へ：**[最新リリース](https://github.com/ixiehao/ShotMap/releases/latest)を開き、Universal `.dmg` をダウンロードして **ShotMap.app** を「アプリケーション」へドラッグしてください。

リリースページには、ダウンロードを確認したい方のために SHA-256 チェックサムも用意されています。ShotMap はまだ Apple の公証を受けていません。macOS に開発元の確認を求められた場合は、「アプリケーション」で Control-click して「開く」を選び、もう一度「開く」を確認してください。macOS 全体のセキュリティ設定を下げる必要はありません。

## プライバシー優先

動画は Mac から外へ出ません。ShotMap はアカウント、追跡、クラウドアップロードを使わず、Electron、FFmpeg、Python ランタイムも含みません。任意の更新確認は GitHub の公開リリース情報だけを読み取り、動画や利用データを送信しません。

## ヘルプ、フィードバック、コミュニティ

- **初めての方へ：**[公式サイト](https://ixiehao.github.io/ShotMap/)で、短い製品紹介と実際のスクリーンショットを確認できます。
- **ヘルプ、不具合、機能の提案：**まず[サポート](SUPPORT.md)を確認してください。再現できる不具合と具体的な提案は [Issue フォーム](https://github.com/ixiehao/ShotMap/issues/new/choose)から送れます。
- **質問や使い方の共有：**[GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions)へどうぞ。
- **開発に参加する：**[CONTRIBUTING.md](CONTRIBUTING.md)をお読みください。セキュリティ上の問題は、非公開の[脆弱性報告フロー](https://github.com/ixiehao/ShotMap/security/advisories/new)を利用してください。
- **プロジェクト情報：**[CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [開発者：ixiehao](https://github.com/ixiehao)

## 権利とライセンス

- ShotMap の Swift ソース、文書、Iris アイコンは本プロジェクトのオリジナルであり、[MIT License](LICENSE) で公開されています。
- アプリは Apple SDK フレームワークだけを使用し、第三者のアプリケーションコード、パッケージ、分析 SDK、MoviePrint 素材を含みません。
- 同梱する [Tabler Icons Outline](https://github.com/tabler/tabler-icons) SVG は未改変で [MIT License](ThirdPartyLicenses/TablerIcons-MIT.txt) に基づいて使用しています。同梱の Noto Sans CJK フォントは [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt) です。詳細は [NOTICE.md](NOTICE.md) を参照してください。
- 文書内のデモ映像は *Tears of Steel*（2012）© Blender Foundation / Blender Institute、[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) ライセンスです。
- 所有している、または解析の許可を得た動画だけを扱ってください。絵コンテの生成は、元動画を公開・再配布する権利を付与しません。

## 開発・保守ドキュメント

[ドキュメント一覧](docs/README.md) · [開発と検証](docs/DEVELOPMENT.md) · [公式サイトの保守](docs/WEBSITE.md)。

公式サイトのソースは `website/` に、開発・保守ドキュメントは `docs/` に置いています。
