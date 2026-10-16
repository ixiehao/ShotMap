# ShotMap

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

![Tears of Steel を処理して絵コンテを作成する ShotMap の日本語ワークスペース](docs/assets/readme-workspace-ja.png?v=tears-20261016)

## 動画を開く前に、中身をひと目で

**ShotMap** は、動画の代表的な場面を一枚の見やすい絵コンテにまとめるネイティブ macOS アプリです。まず絵コンテを見れば、動画の内容や流れをおおまかに把握できます。必要なときだけ元の動画を開けます。

スマート選択で最初の候補を作り、気になるコマだけ手動で置き換えられます。すべての処理は Mac 上で完結します。

> **ShotMap を入手：**[最新 Universal DMG](https://github.com/ixiehao/ShotMap/releases/latest) · macOS 13 以降 · Apple Silicon / Intel Mac 対応

> **デモ映像のクレジット：** *Tears of Steel*（2012）© Blender Foundation / Blender Institute、[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) ライセンス。以下の製品スクリーンショットとアニメーションにはこの映像を使用しています。

## 3 ステップで絵コンテを作成

| 1. 動画を追加 | 2. 場面を選ぶ | 3. 絵コンテを保存 |
| --- | --- | --- |
| 一つの動画をドラッグするか、複数の動画をキューに追加します。 | まずスマート選択を使い、必要なコマだけ手動で調整します。 | 元動画の横に PNG または JPG を書き出します。 |

## 見たい場面をすばやく見つけるために

- 鮮明で代表的な場面を優先し、黒画面、ぼやけ、ほぼ同じコマをできるだけ避けます。
- 手動フレーム選択では、プレーヤー、視覚的タイムライン、コマ送り、候補ギャラリーを一画面で使えます。
- 見えるキューで複数動画を処理し、完成したコマからプレビューへ順に表示します。
- 3 × 3 から 8 × 8 のグリッド、比率、背景色、画像の幅、タイムコード、ファイル名タイトルを選べます。
- MP4、MOV、MPEG など、現在の macOS が対応する動画形式を扱えます。
- English、简体中文、日本語に対応し、ライト、ダーク、システムの外観を選べます。

### 実際の操作を見る

実際のアプリで、完成した絵コンテから手動フレーム選択画面を開き、視覚的なタイムラインで場面を探して候補から一コマを選び、保存する流れです。

![Tears of Steel の絵コンテを表示する ShotMap ワークスペースから手動フレーム選択画面へ移り、視覚タイムラインと候補ギャラリーを表示する操作](docs/assets/video-to-storyboard-demo.gif?v=tears-20261016)

## ダウンロードとインストール

[Homebrew](https://brew.sh/) を使用している場合：

```sh
brew install --cask ixiehao/tap/shottessera
```

または[最新 Universal DMG](https://github.com/ixiehao/ShotMap/releases/latest)をダウンロードし、開いて **ShotMap.app** を「アプリケーション」へドラッグします。

ShotMap はまだ Apple の公証を受けていません。macOS に開発元の確認を求められた場合は、「アプリケーション」で Control-click して「開く」を選び、もう一度「開く」を確認してください。macOS 全体のセキュリティ設定を下げる必要はありません。

## プライバシー優先

動画は Mac から外へ出ません。ShotMap はアカウント、追跡、クラウドアップロードを使わず、Electron、FFmpeg、Python ランタイムも含みません。任意の更新確認は GitHub の公開リリース情報だけを読み取り、動画や利用データを送信しません。

## プロジェクトとフィードバック

- Web サイト：[ixiehao.github.io/ShotMap](https://ixiehao.github.io/ShotMap/)
- ソース、ダウンロード、リリースノート：[github.com/ixiehao/ShotMap](https://github.com/ixiehao/ShotMap)
- 不具合報告・提案：[GitHub Issue を作成](https://github.com/ixiehao/ShotMap/issues/new/choose)
- 開発者：[ixiehao](https://github.com/ixiehao)
- 更新履歴：[CHANGELOG.md](CHANGELOG.md) · プライバシー：[PRIVACY.md](PRIVACY.md)

## 権利とライセンス

- ShotMap の Swift ソース、文書、Iris アイコンは本プロジェクトのオリジナルであり、[MIT License](LICENSE) で公開されています。
- アプリは Apple SDK フレームワークだけを使用し、第三者のアプリケーションコード、パッケージ、分析 SDK、MoviePrint 素材を含みません。
- 同梱する [Tabler Icons Outline](https://github.com/tabler/tabler-icons) SVG は未改変で [MIT License](ThirdPartyLicenses/TablerIcons-MIT.txt) に基づいて使用しています。同梱の Noto Sans CJK フォントは [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt) です。詳細は [NOTICE.md](NOTICE.md) を参照してください。
- 文書内のデモ映像は *Tears of Steel*（2012）© Blender Foundation / Blender Institute、[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) ライセンスです。
- 所有している、または解析の許可を得た動画だけを扱ってください。絵コンテの生成は、元動画を公開・再配布する権利を付与しません。
