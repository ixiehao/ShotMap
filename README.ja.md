<p><img src="website/assets/app-icon.png?v=20261101-release017" width="72" height="72" alt="ShotMap" /></p>

# ShotMap

[![最新リリース](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![検証](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![MITライセンス](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**アプリは7言語に対応：** English · 简体中文 · Français · Русский · Español · 日本語 · 한국어。ひとつのダウンロードにすべて含まれています。

![Tears of Steelの場面を一枚にまとめるShotMapの日本語ワークスペース](website/assets/workspace-ja.webp?v=20261101-release017)

## 動画の場面を、一枚にまとめる。

**ShotMap** は、動画のさまざまな場面を一枚の画像にまとめる、無料・オープンソースのMacアプリです。家族の記録、旅行の動画、編集用の素材を、一本ずつ開いて早送りしなくても見比べられます。

まず自動でコマを選び、必要に応じてタイムラインで差し替えたり、1コマずつ調整したりできます。複数の動画をまとめて処理し、元動画と同じフォルダにPNGやJPGで保存。処理はMac上で完結し、アカウント登録や動画のアップロードは不要です。

> **ここから始める：** [最新国際版をダウンロード](https://github.com/ixiehao/ShotMap/releases/latest) · Apple Silicon / Intel 別の DMG · macOS 13以降 · Apple Silicon / Intel Mac対応

> **デモ映像のクレジット：** *Tears of Steel*（2012）© Blender Foundation / Blender Institute、[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) ライセンス。この文書のスクリーンショットと操作デモに使用しています。

## もう一度見つけたい場面のために

- **家族や個人の記録：** ファイルを一つずつ開かずに、誕生日、旅行、夕日、子どもの成長の場面を探せます。
- **動画制作や編集：** 編集ソフトに読み込む前に、素材をまとめて確認して必要なショットを選べます。
- **動画フォルダの整理：** 各動画と同じフォルダに、場面を一覧できる画像を保存。必要ならタイムコードとファイル名も表示できます。

## 3ステップで場面を一枚に

| 1. 動画を追加 | 2. 場面を選ぶ | 3. 画像を保存 |
| --- | --- | --- |
| 動画を一つ、または複数まとめてドラッグします。 | 自動選択した候補から、必要なコマだけ手動で調整します。 | 元動画と同じフォルダにPNGまたはJPGで保存します。 |

## 場面もレイアウトも、自分で調整

- **まずは自動で選択：**鮮明で変化のある場面を優先し、黒い画面、ぼやけたコマ、よく似た場面をできるだけ減らします。
- **最後は自分で選べる：**プレーヤー、タイムライン、コマ送りで好みの瞬間を探せます。自動選択で追加するときも、すでに選んだコマは残ります。
- **複数の動画をまとめて整理：**一括処理に対応。準備できたコマからプレビューに表示し、処理中の動画が終わったところで一時停止できます。
- **見返しや共有がしやすい画像に：**PNGやJPGで保存。ファイル名やタイムコードを表示すれば、元動画の場面を探すときにも役立ちます。
- **レイアウトも調整：**3 × 3から8 × 8のグリッド、縦横比、画像の幅、背景色を選べます。
- **Macのためのアプリ：**ネイティブ設計で7言語に対応。ライト、ダーク、システムに合わせた外観を選べます。

MP4、MOV、MPEGなど、macOSが対応する動画形式を扱えます。

### 実際の操作を見る

完成した画像から手動コマ選択画面を開き、タイムラインで場面を探して候補を選び、保存する流れです。

![Tears of Steelの場面をまとめたShotMapワークスペースから、タイムラインと候補一覧のある手動コマ選択画面へ移る操作](docs/assets/video-to-storyboard-demo.gif?v=20261101-release017)

## ダウンロードとインストール

[最新リリース](https://github.com/ixiehao/ShotMap/releases/latest)で、Apple Silicon（Mシリーズ）は **arm64**、Intel Macは **x86_64** を選んでください。`.dmg` を開き、**ShotMap.app**を「アプリケーション」へドラッグします。どちらにも7言語すべてが含まれています。

リリースページには、ダウンロードしたファイルを確認するためのSHA-256チェックサムもあります。ShotMapはまだAppleの公証を受けていません。macOSに開発元の確認を求められた場合は、「アプリケーション」でControlキーを押しながらアプリをクリックし、「開く」を選んで、もう一度「開く」を確認してください。macOS全体のセキュリティ設定を下げる必要はありません。

### 表示言語を選ぶ

macOSのメニューバーで表示言語を切り替えられます。再起動は不要で、動画のキューも保持されます。初回起動時は対応するシステム言語を使い、該当しない場合は英語で表示します。その後は選んだ言語を記憶します。

## 動画は手元に

動画はMacに残ります。ShotMapはアカウント、追跡、クラウドアップロードを使わず、Electron、FFmpeg、Pythonランタイムも含みません。任意のアップデート確認ではGitHubの公開リリース情報だけを読み取り、動画や利用データを送信しません。

## ヘルプ、フィードバック、コミュニティ

- **初めての方へ：** [公式サイト](https://ixiehao.github.io/ShotMap/ja/)で製品紹介と実際の画面をご覧いただけます。
- **ヘルプ、不具合、機能の提案：** まず[サポート](SUPPORT.md)をご確認ください。再現できる不具合や具体的な機能提案は[Issueフォーム](https://github.com/ixiehao/ShotMap/issues/new/choose)から送れます。
- **質問や使い方の共有：** [GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions)へどうぞ。
- **開発に参加する：** [CONTRIBUTING.md](CONTRIBUTING.md)をお読みください。セキュリティ上の問題には非公開の[脆弱性報告窓口](https://github.com/ixiehao/ShotMap/security/advisories/new)をご利用ください。
- **プロジェクト情報：** [CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [開発者：ixiehao](https://github.com/ixiehao)

## 権利とライセンス

- ShotMapのSwiftソース、文書、アプリアイコンは本プロジェクトのオリジナルであり、[MITライセンス](LICENSE)で公開しています。
- アプリはApple SDKのフレームワークのみを使用し、第三者のアプリケーションコード、パッケージ、分析SDK、MoviePrint素材を含みません。
- 同梱の[Tabler Icons Outline](https://github.com/tabler/tabler-icons) SVGは未改変で、[MITライセンス](ThirdPartyLicenses/TablerIcons-MIT.txt)に基づいて使用しています。Noto Sans CJKフォントは[SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt)に基づきます。詳細は[NOTICE.md](NOTICE.md)をご覧ください。
- 文書内のデモ映像は*Tears of Steel*（2012）© Blender Foundation / Blender Institute、[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)ライセンスです。
- 所有している、または解析の許可を得た動画だけを扱ってください。画像の生成は、元動画を公開・再配布する権利を付与しません。

## 開発・保守ドキュメント

[ドキュメント一覧](docs/README.md) · [開発と検証](docs/DEVELOPMENT.md) · [公式サイトの保守](docs/WEBSITE.md)

公式サイトのソースは `website/` に、開発・保守ドキュメントは `docs/` にあります。
