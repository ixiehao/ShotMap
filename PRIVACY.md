# Privacy / 隐私 / プライバシー

## English

ShotMap processes a video entirely on the device that opens it.

- No user account or analytics SDK is included.
- No video, frame, path, face-detection result, or generated storyboard is sent over the network.
- The app does not keep an internal media library. It saves generated images beside the selected video; Save As lets you choose another location. If saving fails, it temporarily caches the result on this Mac so you can retry. These temporary previews are removed when their history is cleared or the owning session is released.
- Apple's AVFoundation and Vision frameworks perform decoding and people/face detection locally.
- To check for a newer app version, the app reads only public latest-release metadata from GitHub. The request contains no video, file path, frame, account, or analytics data; downloading happens only after the user chooses it in their browser.

If this changes in a future release, the change must be documented here and in the release notes before it ships.

## 中文

视频一键拼图（ShotMap）会完全在打开视频的设备上处理视频。

- 不包含用户账号或分析 SDK。
- 不会经由网络发送视频、画面、文件路径、人脸检测结果或生成的分镜图。
- 应用不会保留内部媒体资料库。生成的图片自动保存到所选视频旁边，也可以通过“另存为”选择其他位置。保存失败时，结果会暂存在本机，方便重试；清空结果历史或相应会话释放时，会清理这些临时预览。
- Apple 的 AVFoundation 与 Vision 框架会在本地执行解码和人物／人脸检测。
- 检查新版本时，应用只读取 GitHub 的公开最新发布元数据。该请求不包含视频、文件路径、画面、账号或分析数据；只有用户在浏览器中主动选择后才会下载。

未来版本如有变化，必须在发布前同时更新本文档与版本说明。

## 日本語

ShotMap は、開いた動画をそのデバイス上で完結して処理します。

- ユーザーアカウントや分析 SDK は含まれません。
- 動画、フレーム、パス、顔検出結果、生成した絵コンテをネットワークへ送信しません。
- アプリ内のメディアライブラリは保持しません。生成した画像は選択した動画と同じフォルダに保存され、「名前を付けて保存」で別の場所も選べます。保存に失敗した場合は再試行できるよう、この Mac に結果を一時保存します。一時プレビューは履歴の消去時、または対応するセッションの解放時に削除されます。
- Apple の AVFoundation と Vision フレームワークが、デコードと人物／顔検出をローカルで行います。
- 新しいバージョンを確認する際、アプリは GitHub の公開された最新リリースメタデータのみを読み取ります。リクエストに動画、ファイルパス、フレーム、アカウント、分析データは含まれず、ダウンロードはユーザーがブラウザで選択した場合にのみ行われます。

今後のリリースでこれが変わる場合は、公開前にこの文書とリリースノートの両方へ記載する必要があります。
