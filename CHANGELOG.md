# Changelog

All notable user-facing changes are recorded here. Stable releases remain
available on the [GitHub Releases page](https://github.com/ixiehao/ShotMap/releases).

## v0.2.13

### English

- Rebuilt the Batch Studio workspace with a calmer three-pane layout, a sharper visual hierarchy, compact header controls, and consistent light and dark palettes.
- Redesigned Manual Frame Editor as a focused editing desk: player, visual timeline, frame-step controls, selectable candidates, and selection order all remain visible together.
- Replaced the generic grid controls with clear visual grid choices, refined the queue action, and refreshed the ShotMap icon across the app and public surfaces.
- Updated the official website and three README files with real *Tears of Steel* product captures in English, Chinese, and Japanese. Demo footage is credited to Blender Foundation / Blender Institute under CC BY 3.0.
- Simplified the documentation by removing the image-heavy installation guide while retaining concise, safe installation steps.

### 中文

- 重构 Batch Studio 主工作区：采用更安静清晰的三栏布局、紧凑的顶部控件，并统一优化浅色和深色配色。
- 重新设计手动选帧窗口：播放器、可视化时间轴、逐帧调整、候选画面和选中顺序可同时查看与操作。
- 将普通网格按钮替换为更直观的可视化网格选择器，优化视频队列添加操作，并同步更新 ShotMap 图标及公开素材。
- 官网与三语 README 已改用真实运行的《Tears of Steel》软件截图；英文、中文、日文均提供对应界面，且明确署名 Blender Foundation / Blender Institute 的 CC BY 3.0 演示视频授权。
- 移除偏重图片的安装指南，文档保留更简洁、安全的文字安装步骤。

### 日本語

- Batch Studio のメイン画面を再構築し、落ち着いた 3 ペイン構成、明確な情報階層、コンパクトなヘッダー操作、統一したライト／ダーク配色へ刷新しました。
- 手動フレーム選択画面を、プレーヤー、視覚的タイムライン、コマ送り、候補、選択順を同時に確認できる編集画面として再設計しました。
- 通常のグリッドボタンを視覚的にわかりやすいグリッド選択へ置き換え、キュー追加操作と ShotMap アイコン、公開素材を改善しました。
- 公式サイトと 3 言語の README を、実際に動作する *Tears of Steel* のキャプチャへ更新しました。英語・中国語・日本語で対応する UI を表示し、Blender Foundation / Blender Institute による CC BY 3.0 の映像を明記しています。
- 画像中心のインストールガイドを削除し、簡潔で安全なテキスト手順を残しました。

## v0.2.12

### English

- ShotTessera is now **ShotMap**: a shorter, easier-to-remember product name. The Chinese product label is now **视频一键拼图**.
- Updated the app name, About and Help views, DMG installer, README files, website, and public product imagery in English, Chinese, and Japanese. GitHub links, update checks, and the official Pages address now use the new ShotMap URLs; the former GitHub repository address continues to redirect.
- Refreshed the existing real product captures with the new name while preserving their original footage and workflows.
- Batch-complete messages now follow the current app language when you switch languages after a run.

### 中文

- **ShotTessera** 现更名为 **ShotMap**，名称更简洁、更容易记忆；中文产品名调整为 **视频一键拼图**。
- 已同步更新应用名称、“关于”与帮助界面、DMG 安装器、README、官网及公开产品截图，覆盖英文、中文和日文；GitHub 链接、应用内更新检查和官网地址均已切换至新的 ShotMap URL，旧 GitHub 仓库地址仍会自动跳转。
- 在保留原始演示视频内容与操作流程的前提下，更新现有真实产品截图中的品牌文字。
- 批处理结束后再切换语言，完成提示也会立即显示为当前界面语言。

### 日本語

- **ShotTessera** を、より短く覚えやすい **ShotMap** へ名称変更しました。中国語の製品名も **视频一键拼图** に更新しています。
- アプリ名、「情報」とヘルプ、DMG インストーラ、README、Web サイト、公開プロダクト画像を英語・中国語・日本語で更新しました。GitHub リンク、アプリ内の更新確認、公式 Pages の URL は新しい ShotMap の URL へ切り替え、以前の GitHub リポジトリ URL は自動的に転送されます。
- 元の映像素材と操作フローはそのままに、既存の実機キャプチャ内のブランド表記を更新しました。
- バッチ処理後に表示言語を切り替えた場合も、完了メッセージが現在の言語にすぐ切り替わります。

## v0.2.11

### English

- Refreshed the whole workspace with a consistent Tabler Icons Outline system, including the queue, preview, settings, batch controls, and Manual Frame Editor.
- Improved the visual hierarchy of icon labels, section badges, and action controls in both Light and Dark appearance modes, so common tasks are easier to find at a glance.
- Bundled the local icon assets and added their MIT attribution to the app's notices.

### 中文

- 全面采用统一的 Tabler Icons Outline 图标系统，覆盖视频队列、预览、设置、批处理控制和手动选帧窗口。
- 优化浅色与深色模式下的图标标签、分区标识和操作控件层级，让常用功能更易识别。
- 内置本地图标资源，并在项目声明中补充相应的 MIT 致谢。

### 日本語

- キュー、プレビュー、設定、バッチ操作、手動フレーム選択を含むワークスペース全体を、統一した Tabler Icons Outline のアイコン体系へ刷新しました。
- ライト／ダーク表示の両方で、アイコン付きラベル、セクションバッジ、操作コントロールの情報階層を改善し、よく使う機能を見つけやすくしました。
- ローカルのアイコン素材を同梱し、プロジェクトの表記に MIT ライセンスの帰属情報を追加しました。

## v0.2.10

### English

- Made the first storyboard preview progressive: a stable grid appears immediately, representative frames fill their final positions in order, then sharper captures replace them in place.
- Made Manual Frame Editor candidate loading and Apply faster by decoding the chosen moment first and expanding to nearby frames only when motion blur, a dissolve, or a decode failure needs recovery.
- Kept action-heavy material protected: low-clarity and movement-risk frames still use the full local sharpness search instead of trading image quality for speed.
- Improved Manual Frame Editor reliability and accessibility: it remembers its size and position, no longer offers an unrecoverable minimise action, keeps selections when appearance changes, and supports Escape / Command–Return shortcuts.
- Improved media-error guidance and added stricter universal-build, concurrency, and release verification gates for contributors.

### 中文

- 首次生成分镜图改为渐进预览：网格会立即出现，代表性画面按最终位置依次填入，随后在原位替换为更清晰的精修画面。
- 手动选帧候选区与“应用并保存”改为先取目标时刻；仅在运动模糊、转场或取帧失败时才扩展到相邻帧，减少不必要的解码等待。
- 动作素材继续受到保护：清晰度不足或存在运动风险的画面仍会执行完整局部清晰度搜索，不以速度牺牲画质。
- 提升手动选帧窗口的可靠性与辅助功能：记住位置和尺寸，移除无法恢复的最小化操作，切换外观时保留选择，并支持 Escape / Command–Return 快捷键。
- 改进媒体错误提示，并为贡献者增加更严格的通用构建、并发与发布验证流程。

### 日本語

- 最初の絵コンテ表示を段階的にしました。安定したグリッドをすぐに表示し、代表フレームを最終位置へ順に配置した後、より鮮明なフレームへその場で置き換えます。
- 手動フレーム選択の候補読み込みと「適用して保存」を高速化しました。まず指定時刻を取得し、モーションブラー、ディゾルブ、取得失敗時だけ近傍フレームを追加で調べます。
- 動きの多い素材の品質は維持します。低鮮明度または動きのリスクがあるフレームでは、速度優先で画質を落とさず、従来どおり局所的な鮮明度検索を行います。
- 手動フレーム選択ウインドウの信頼性とアクセシビリティを改善しました。位置とサイズを記憶し、復元不能な最小化操作をなくし、表示モード変更時も選択を保持し、Escape / Command–Return に対応します。
- メディアエラーの案内を改善し、貢献者向けに Universal Build、並行性、リリース検証をより厳格にしました。

## v0.2.9

### English

- Hotfix: corrected appearance switching so text, settings, and controls immediately use the matching semantic colours in Light and Dark mode, including the Manual Frame Editor.
- Optimised the AVFoundation and Vision pipeline for macOS 27: batch precise frame extraction, reuse Vision previews, and avoid redundant decoding.
- Added adaptive 3 × 3 / 4 × 4 low-resolution broad scans with full-resolution final-frame retrieval, while preserving the existing visual-quality rules.
- Added text-region-first screening with OCR fallback to keep title cards and warnings out without penalising ordinary subtitles.

### 中文

- 热修复：修正显示模式切换；浅色与深色模式下的文字、设置项和控件会立即使用匹配的语义颜色，“手动选择画面”窗口也已同步。
- 借助 macOS 27 的 AVFoundation 与 Vision 调度能力优化处理管线：批量精确取帧、复用 Vision 预览，并减少重复解码。
- 为 3 × 3 / 4 × 4 增加自适应低分辨率粗筛与最终高分辨率回读，同时保持既有画质判断规则。
- 新增“文字区域优先、OCR 回退”的筛选方式：继续拦截封面和警告图，不误伤普通字幕。

### 日本語

- 修正：表示モード切り替えを修正しました。ライト／ダークで文字・設定項目・コントロールが直ちに正しいセマンティックカラーへ切り替わり、手動フレーム選択画面にも適用されます。
- macOS 27 の AVFoundation と Vision の実行特性を活かし、精密フレーム抽出のバッチ化、Vision プレビューの再利用、重複デコードの削減を行いました。
- 3 × 3 / 4 × 4 では低解像度の粗い走査と最終フレームの高解像度取得を適応的に行い、既存の画質判定を維持します。
- テキスト領域の検出を優先し、必要時のみ OCR にフォールバックすることで、通常の字幕を避けつつ表紙・警告画面を除外します。

## v0.2.8

### English

- Improved the manual frame-selection window with a redesigned player, timeline, and candidate gallery layout.
- Added storyboard background-colour selection to Frame settings.

### 中文

- 优化手动选帧窗口：重做整体布局为“播放器 + 时间线 + 候选画廊”。
- 在“画面”设置中增加“底色”选择。

### 日本語

- 手動フレーム選択ウインドウを、プレーヤー、タイムライン、候補ギャラリーの構成に再設計しました。
- 「画面」設定に絵コンテの背景色選択を追加しました。

## v0.2.7

### English

- Refined the Batch Studio’s three-column layout, spacing, minimum window size, and queue scrolling.
- Redrew the original vector icon system and improved preview-navigation contrast in Light and Dark modes.

### 中文

- 全面重构批处理工作台的三栏布局、间距、最小窗口尺寸与队列滚动体验。
- 重绘全套原创矢量界面图标；提升浅色与深色模式下预览翻页按钮的辨识度。

### 日本語

- バッチ作業画面の 3 カラム構成、余白、最小ウインドウサイズ、キューのスクロール体験を改善しました。
- オリジナルのベクターアイコンを再設計し、ライト／ダーク表示でのプレビュー移動ボタンの視認性を高めました。

## v0.2.6

### English

- Added Light, Dark, and System appearance modes; improved window restoration and three-language layouts.
- Improved large-batch reliability with background saves, low-memory history, and clearer failure handling.

### 中文

- 新增浅色、深色与跟随系统外观；优化窗口恢复和三语言布局。
- 提升超大批次稳定性：后台保存、低内存历史预览与更准确的失败处理。

### 日本語

- ライト、ダーク、システム連動表示を追加し、ウインドウ復元と 3 言語レイアウトを改善しました。
- バックグラウンド保存、省メモリ履歴、明確な失敗処理で大規模バッチを安定化しました。

## v0.2.5

### English

- Added GitHub update reminders in the main window, About panel, and Help menu.
- Update checks read public release metadata only; no video or usage data is sent.

### 中文

- 新增 GitHub 更新提醒：主界面、关于与帮助均可直接前往下载新版本。
- 更新检查仅读取公开版本信息，不上传视频或使用数据。

### 日本語

- メイン画面、情報画面、ヘルプメニューに GitHub の更新通知を追加しました。
- 更新確認は公開リリース情報のみを読み取り、動画や利用データを送信しません。

## v0.2.4

### English

- Batch runs can safely pause/resume or stop with confirmation; a pause takes effect after the current video is saved.
- A failed video no longer stops the queue; review its error and retry only failed items afterward.

### 中文

- 批处理新增安全暂停/继续与停止确认；暂停会在当前影片保存后生效，可调整未处理影片的配置。
- 单个影片失败不会中断队列；结束后可查看失败原因并仅重试失败项。

### 日本語

- バッチ処理に確認付きの安全な一時停止・再開・停止を追加。停止は現在の動画を保存した後に反映されます。
- 1 本の失敗でキュー全体は止まらず、終了後に原因を確認して失敗分だけ再試行できます。

## v0.2.3

### English

- Added manual frame selection: browse candidates, use Smart Select, then fine-tune before creating the storyboard.
- Browse batch results with previous/next controls and open the saved image’s folder directly.
- Improved batch reliability and memory protection for large exports.
- Redesigned the DMG with an aligned drag-to-Applications layout and automatic final-package and universal-binary validation.
- Replaced the synthetic README sample with an owner-shot real-world result and refreshed the three-language visual install guides.

### 中文

- 新增手动选择画面：可浏览候选截图、智能一键选帧，再按需微调后生成。
- 批量结果支持左右切换；保存后可直接打开所在目录。
- 优化批处理稳定性与大尺寸导出的内存保护。
- 重新设计 DMG 安装器：应用、箭头与“应用程序”对齐，并自动校验最终安装包与双架构。
- README 改用项目所有者自摄视频的真实生成案例，并更新三语图文安装指南。

### 日本語

- 手動フレーム選択を追加：候補を確認し、スマート選択後に調整してから生成できます。
- バッチ結果を前後に切り替えられ、保存後は画像のフォルダを直接開けます。
- バッチ処理の安定性と大きな出力時のメモリ保護を改善しました。
- DMG を再設計し、アプリ・矢印・「アプリケーション」を整列。最終 DMG と Universal Binary を自動検証します。
- README を所有者撮影の実例に更新し、3 言語の画像付きインストールガイドを刷新しました。

## v0.2.2 — Stable

### English

- Universal DMG for Apple Silicon and Intel Macs.
- English, 中文, and 日本語 interfaces with an easier language selector.
- Source, landscape, square, portrait, and common aspect layouts; aspect and
  width use matching dropdown panels.
- Batch processing, live previews, PNG/JPG, timecodes, and filename titles.
- The About panel links to developer ixiehao, the project, and feedback.

### 中文

- 同时支持 Apple Silicon 与 Intel Mac 的通用 DMG。
- 支持 English、中文、日本語；语言选择更易点击。
- 支持横屏、方屏、竖屏及常见比例；比例和宽度均使用统一的下拉选择面板。
- 支持批量视频、实时预览、PNG/JPG、时间码和文件标题水印。
- “关于”页提供开发者 ixiehao、项目主页和反馈入口。

### 日本語

- Apple Silicon / Intel Mac 向け Universal DMG。
- English、中文、日本語に対応し、言語選択を操作しやすく改善。
- 元動画、横長、正方形、縦長などの比率に対応。比率と幅を統一した
  ドロップダウンで選択可能。
- 複数動画、リアルタイムプレビュー、PNG/JPG、時刻表示、ファイル名タイトルに対応。
- 「情報」画面から開発者 ixiehao、プロジェクト、フィードバックを確認可能。
