# Contributing / 参与贡献 / コントリビューション

## English

Thank you for improving ShotMap.

1. Search existing issues before opening a new one.
2. Keep a contribution focused: one bug fix, feature, or documentation change per pull request.
3. Do not add telemetry, accounts, cloud upload, network clients, bundled media runtimes, or new third-party assets without explaining why.
4. Do not commit private videos, generated storyboards, credentials, or large binary test media.
5. Run `swift test` before submitting code. Changes to selection, rendering, export, or localisation should include an appropriate test or manual verification note.

By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

### Local verification

Before opening a pull request, run:

```sh
swift test
swift build -c release --arch arm64 --arch x86_64
```

For changes to decoding, rendering, export, pause/cancel, or manual selection,
also verify one non-private H.264 or HEVC file manually: complete an export,
cancel an active run, and retry a temporary output-folder failure. Do not upload
the source file with the issue or pull request; record only the macOS version,
Mac type, container/codec, duration, and the reproduced result.

## 中文

感谢你改进视频一键拼图（ShotMap）。

1. 新建 Issue 前，请先搜索现有 Issue。
2. 每个 Pull Request 请聚焦于一项修复、功能或文档改动。
3. 未说明理由前，请勿加入遥测、账号、云上传、网络客户端、内置媒体运行时或新的第三方资源。
4. 请勿提交私人视频、生成的分镜图、凭据或大型二进制测试媒体。
5. 提交代码前运行 `swift test`。涉及选帧、渲染、导出或本地化的改动，应附带适当的测试或人工验证说明。

参与本项目即表示你同意遵守[行为准则](CODE_OF_CONDUCT.md)。

### 本地验证

提交 Pull Request 前，请运行：

```sh
swift test
swift build -c release --arch arm64 --arch x86_64
```

如果改动了解码、渲染、导出、暂停/取消或手动选帧，请再使用一个非私人的 H.264 或 HEVC 视频手动验证：完成一次导出、取消运行中的任务，并在暂时无法写入输出文件夹后执行重试。请不要在 Issue 或 Pull Request 中上传源视频；只需记录 macOS 版本、Mac 类型、封装/编码格式、时长和复现结果。

## 日本語

ShotMap の改善にご協力いただき、ありがとうございます。

1. 新しい Issue を作成する前に、既存の Issue を検索してください。
2. 1 つの Pull Request では、1 件のバグ修正、機能、またはドキュメント変更に集中してください。
3. 理由を説明せずに、テレメトリー、アカウント、クラウドアップロード、ネットワーククライアント、同梱メディアランタイム、新しい第三者素材を追加しないでください。
4. 私的な動画、生成した絵コンテ、認証情報、大きなバイナリのテスト媒体をコミットしないでください。
5. コードを送る前に `swift test` を実行してください。選択、描画、書き出し、ローカライズに関する変更には、適切なテストまたは手動検証の注記を含めてください。

参加することで、[行動規範](CODE_OF_CONDUCT.md)に従うことに同意したものとします。

### ローカルでの確認

Pull Request を開く前に、以下を実行してください。

```sh
swift test
swift build -c release --arch arm64 --arch x86_64
```

デコード、描画、書き出し、一時停止/キャンセル、手動選択に変更を加えた場合は、私人的ではない H.264 または HEVC の動画を 1 本使い、書き出しの完了、実行中のキャンセル、一時的な出力フォルダーの書き込み失敗からの再試行を手動で確認してください。Issue や Pull Request に元動画はアップロードせず、macOS のバージョン、Mac の種類、コンテナ/コーデック、尺、再現結果のみを記録してください。
