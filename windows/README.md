# ShotMap Windows 首轮原型

主窗口按 Mac 版简体中文浅色工作区布局实现。左侧是带编号、状态和添加入口的视频队列，中间是分镜预览，右侧是分镜设置。工具栏上的两个侧栏按钮可独立收起面板，「专注预览」一键收起两栏，再次点击还原之前的组合。全局底栏居中显示结果页码，两侧是本机处理提示和手动选帧入口。

在 Windows 11 x64 上可以多选或拖入本地视频。ShotMap 按队列顺序生成分镜，单项失败时继续处理后续视频。点击「当前视频完成后暂停」可在两段视频之间调整参数，继续后新参数只用于尚未开始的视频。用底栏的上一张、下一张箭头浏览已生成分镜，也可直接选择队列里的视频。用「停止本次生成」或 `Esc` 取消，已完成的结果可以继续导出。

右栏提供 3 × 3 至 8 × 8 的六种可视网格、画面比例、1920 至 3840 px 宽度、六种背景色、时间码、文件名和视频信息开关。视频信息包含可读取的时长、文件大小、分辨率、平均帧率、视频编码、视频码率和音频编码。修改布局后点工具栏的「生成分镜图」更新。有效画面不足时，余下格位留空。

「手动选帧」采用 Mac 版的窗口布局。上方左侧是预览，右侧是带选中编号的胶片时间轴，下方是候选图。点击候选图可选中或取消选中，分镜按源视频时间排序。达到格数上限后，先取消一张再选替换帧。拖动时间轴，或在时间框输入时间码或秒数并按 `Enter` 定位。用 `−5 帧`、`−1 帧`、`+1 帧`、`+5 帧` 微调，再用「添加当前帧」将画面放入候选图。播放取决于 Windows 上可用的视频解码器。

「智能选帧」保留已选画面并补选，「换一批」重新采样并清空当次选择。点击「保存」更新当前分镜，保留原版式，再回主窗口导出。`Ctrl+O` 添加视频，`Ctrl+S` 另存所选分镜。可在右栏或另存为窗口切换 PNG、JPG、WebP。点击「批量导出」可将已生成的分镜统一保存到一个目录，同名时自动递增序号。

默认宽度为 1920 px，按显示方向保持源比例，使用象牙底色、时间码和 JPG。预览与导出共用同一张合成图。应用在本机解码、选帧和编码，无需账号或联网。Windows 版使用 WPF/WIC 渲染和编码 PNG、JPG，使用 FFmpeg 的 `libwebp` 编码无损 WebP。本地产物为依赖 .NET Desktop Runtime 的 x64 原型。

## 运行便携预览版

从 [GitHub Releases](https://github.com/ixiehao/ShotMap/releases) 下载 Windows x64 ZIP 并完整解压。便携包内含 x64 .NET 10 Desktop Runtime。另从 [FFmpeg 的 Windows 下载页](https://ffmpeg.org/download.html#build-windows) 获取含 `ffmpeg.exe` 和 `ffprobe.exe` 的 x64 构建，启用 WebP 导出时使用带 `libwebp` 的版本。把 FFmpeg 的 `bin` 文件夹放在 ShotMap 目录下的 `ffmpeg` 文件夹里，或把 `bin` 加入 PATH，再打开 `ShotMap.exe`。预览包采用 ZIP 分发，应用未做 Authenticode 签名。

## 在本机构建

在仓库根目录执行。以下命令使用这台 PC 已备好的公共依赖。若已在系统中安装 x64 .NET 10 SDK 和 FFmpeg，可以用 `dotnet` 代替 `$dotnet`，并从 PATH 找到 `ffmpeg.exe` 和 `ffprobe.exe`。显式指定媒体工具时，使用实际 exe 的绝对路径。

```powershell
$env:DOTNET_ROOT_X64 = (Resolve-Path '..\公共依赖库\dotnet-10-x64').Path
$dotnet = Join-Path $env:DOTNET_ROOT_X64 'dotnet.exe'
$media = (Resolve-Path '..\公共依赖库\ffmpeg-9.1-essentials_build\bin').Path
$env:SHOTMAP_FFMPEG = Join-Path $media 'ffmpeg.exe'
$env:SHOTMAP_FFPROBE = Join-Path $media 'ffprobe.exe'

& $dotnet build windows/ShotMap.Windows -c Release -warnaserror
& $dotnet publish windows/ShotMap.Windows -c Release --no-restore --self-contained false -o windows/artifacts/workspace
& .\windows\artifacts\workspace\ShotMap.exe
```

已有产物时，可在设置上述环境变量后直接运行最后一条命令。将 `artifacts/workspace/` 作为一个目录保留。构建还原没有外部 NuGet 包。若受管会话禁止访问用户 NuGet 配置，可在构建会话中运行以下两行，将 CLI 缓存和配置重定向到项目的忽略目录。

```powershell
$env:DOTNET_CLI_HOME = Join-Path (Get-Location) 'windows\artifacts\sdk'
$env:APPDATA = $env:DOTNET_CLI_HOME
```

在提交 Windows 源码后，可以用同一套 x64 SDK 与 Desktop Runtime 生成发布 ZIP、版权声明、构建信息和 SHA-256 文件。产物写入 `windows/artifacts/releases/`。

```powershell
powershell -NoProfile -ExecutionPolicy RemoteSigned -File windows/Package-Preview.ps1 -DotnetRoot $env:DOTNET_ROOT_X64 -RuntimeVersion 10.0.15
```

## 验收入口与产物

验收程序调用与窗口共用的解码、选帧、渲染和编码代码。素材由 FFmpeg 合成。夹具脚本需要支持 `libx264`、`libx265` 和 `drawtext` 的构建，以及 Windows 系统的 Consolas 字体。每次使用一个新的输出目录，保留之前的产物。

```powershell
$run = Join-Path 'windows/artifacts' ('qa-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$fixtures = powershell -NoProfile -ExecutionPolicy Bypass -File windows/tests/New-Fixtures.ps1 -Output "$run/fixtures"
& $dotnet build windows/tests -c Release -warnaserror -o windows/artifacts/verify
& $dotnet windows/artifacts/verify/ShotMap.Verify.dll $fixtures "$run/samples"
```

附加入口使用现有合成素材和获授权的手机实拍文件。拖放验收窗口在发布版同一份 WPF 窗口上加了一个测试拖放源。把标记的拖放源拖到中间画布，程序会通过系统 `FileDrop` 把文件路径递给 ShotMap。

```powershell
& $dotnet windows/artifacts/verify/ShotMap.Verify.dll --desktop-drag `
  (Join-Path $fixtures 'rotation VFR.mov') (Join-Path $fixtures '测试素材 H264.mp4')
& $dotnet windows/artifacts/verify/ShotMap.Verify.dll --phone `
  'windows/artifacts/verified/phone/train.mov' "$run/phone"
```

| 内容 | 本轮路径 |
| --- | --- |
| 三栏工作区入口 | `windows/artifacts/workspace/ShotMap.exe` |
| 本轮主窗口批量导出的两个 WebP | `windows/artifacts/verified/workspace-mac/导出/` |
| 本轮主窗口另存的 4 × 4 PNG | `windows/artifacts/verified/workspace-mac/素材/2-宽屏 VFR-shot-001.png` |
| 本轮三栏回归和拖放记录 | `windows/artifacts/verified/workspace-mac/final-results.txt`、`windows/artifacts/verified/workspace-mac/drag.txt` |
| 横屏、VFR、旋转竖屏及 HEVC 样例 | `windows/artifacts/verified/samples/`，各含 PNG、JPG 和 CSV |
| 有效画面不足样例 | `windows/artifacts/verified/samples/静态 不足九格.png` |
| WPF 窗口导出的竖屏 JPG | `windows/artifacts/verified/fixtures/测试素材 01/rotation VFR-shot-001.jpg` |
| WPF 窗口切换格式导出的 PNG | `windows/artifacts/verified/fixtures/测试素材 01/quality-shot-001.png` |
| 4 × 4 批量 PNG 和拖放记录 | `windows/artifacts/verified/desktop/batch/`、`windows/artifacts/verified/desktop/drag.txt` |
| 新版手动选帧窗口导出的 PNG | `windows/artifacts/verified/manual-redesign/素材/宽屏 VFR-shot-001.png` |
| 参数和手动选帧回归图 | `windows/artifacts/verified/manual-redesign/samples/` |
| 手动选帧改版回归日志 | `windows/artifacts/verified/manual-redesign/results.txt` |
| iPhone 样本分镜、PTS 和日志 | `windows/artifacts/verified/phone/samples/`、`windows/artifacts/verified/phone/results.txt` |

`bin/`、`obj/` 和 `artifacts/` 已忽略。`ShotMap.Core/` 实现取帧、评分、选择和布局，`ShotMap.Windows/` 实现窗口、渲染和导出，`tests/` 保存夹具脚本和验收程序。窗口和 EXE 使用仓库现有的 ShotMap 图标。FFmpeg 和 ffprobe 作为外部运行依赖，从本机调用。

## 2026-11-22 实测

Windows 11 专业版 21H2 x64，构建 22000，Intel Core i5-7400，15.96 GiB 内存。使用 .NET SDK `10.0.404`、Windows Desktop Runtime `10.0.15` 和 Gyan FFmpeg／ffprobe `9.1-essentials_build` x64。工作区 `ShotMap` 原有一份未跟踪的交接文档。`origin/main` 和本地 `feature/shotmap-windows` 的开发基线均为 `5ac4516e474f3ed20ca345e4198481ea67449886`。完整下载中断后，采用浅层稀疏检出，已取出源码、项目文档和窗口图标，部分 Mac 与官网二进制资源留在远端。原有交接文档保留在原处。

Release 构建及验收程序构建均为 0 警告、0 错误。以下合成样本为首轮顺序运行的一次实测，iPhone 为补充验收的单独一轮。H.264 是首轮验收进程内首个预览，其余合成样本为同进程后续用例。首张预览计到 WPF 完成整张合成图，合计时间计到 PNG 和 JPG 均落盘。每 20 ms 采样验收进程和当时运行的媒体子进程工作集之和。数值含该进程中的 WPF 与缓存，随测试顺序和系统负载变化。

| 素材 | 通过结果 | 预览 | 含两次导出 | 合计峰值 |
| --- | --- | ---: | ---: | ---: |
| H.264 MP4，中文和空格路径 | 9 张，1920 × 1127，PNG／JPG 可读 | 886 ms | 1207 ms | 94.8 MiB |
| H.264 VFR MP4 | 9 张，1920 × 1127，实际 PTS 与逐帧像素一致 | 619 ms | 774 ms | 138.3 MiB |
| 带 90° 显示矩阵的 VFR MOV | 解码画面 360 × 640，四角颜色位置正确，分镜 1920 × 3326 | 923 ms | 1380 ms | 157.4 MiB |
| HEVC MP4 | 9 张，1920 × 1127，PNG／JPG 可读 | 1545 ms | 1702 ms | 190.2 MiB |
| iPhone 12 Pro HEVC VFR MOV | 9 张，1920 × 3326，旋转方向和源帧身份通过 | 26593 ms | 27294 ms | 181.2 MiB |

- **VFR 与旋转**。夹具相邻帧间隔为 49 和 157 ms。验收先用 `ffprobe -show_frames` 查到选中 PTS 对应的源帧序号，再按序号独立解码，与高清回读的 BGR 逐字节比较。MP4 选中的首三帧为 `571`、`1817`、`3014`，时间基 `1/1000`。MOV 选中的首三帧为 `7536`、`27472`、`46624`，时间基 `1/16000`。两者均匹配源帧序号 `3,13,22,30,39,49,58,66,75`。CSV 记录流、时间基、PTS、编码尺寸、旋转、解码尺寸、显示秒数和画面 SHA-256。
- **选帧**。混合素材采样 90 帧，拒绝 10 张黑屏、10 张严重模糊和 30 张近重复。静态清晰素材保留 1 张有效帧，分镜其余 8 格留空。
- **故障与取消**。损坏 MP4 得到 ffprobe 错误。在 FFmpeg 已启动时取消，从探测开始约 254 ms 返回，记录的实际解码 PID 已退出。随后重新取帧成功。拒绝写入的目录没有生成文件，恢复目录权限后导出成功。同名文件拒绝覆盖时，原成品散列一致且临时文件清理完成。预先取消的导出没有生成文件。参与散列检查的源文件内容一致。
- **WPF 实际窗口**。启动交付目录中的 `ShotMap.exe`，在「打开视频」选择含中文和空格路径的旋转 VFR MOV。界面报告 9 张画面，通过 `Ctrl+S` 保存默认 JPG。磁盘上验收程序和窗口导出的竖屏 JPG 一致。
- **窗口内切换 PNG**。在「导出分镜」将保存类型从 JPG 切换到 PNG，默认扩展名自动切换，状态栏报告成功。ffprobe 复读 `quality-shot-001.png`，为 1920 × 1127 的 RGBA PNG。
- **实际文件拖放与批量处理**。资源管理器跨窗口拖放受桌面自动化工具的边界限制。本机从验收窗口的 WPF 拖放源发起实际 `FileDrop`，系统返回 `Copy`，含中文和空格路径的旋转 MOV 与 H.264 MP4 同时入队并顺序生成。右栏切换到 4 × 4 后，两项均更新为 16 张。切换 PNG 后批量导出 2 个文件，ffprobe 分别读到 1920 × 3320 和 1920 × 1132。已有 `-shot-001.png` 的散列一致，新增旋转图使用 `-shot-002.png`。
- **预览翻页、视频信息与旧版格位编辑**。从发布版窗口一次选入横屏和旋转样本，确认视频信息叠加、`1 / 2` → `2 / 2` → `1 / 2` 和两端按钮状态。旧版格位编辑器把旋转 VFR 分镜首帧从 `00:00:00.471` 改为 `00:00:00.157`。导出的 1920 × 3326 RGBA PNG 第一格内部像素发生变化，第二格的对照区域像素一致。
- **新版手动选帧**。在发布版窗口导入中文路径中的横屏和旋转竖屏 VFR，检查横屏四列、竖屏六列、显示方向、时间轴、选中编号和手动候选标签。拖动横屏样本的播放头定位到第 35 帧，连续前进一帧依次到 `00:00:04.631`、`00:00:04.680` 和 `00:00:04.837`，相邻间隔为 49 和 157 ms。添加第 37 帧、替换原第 39 帧、保存，并在另存为切换 PNG。主窗口分镜第五格显示第 37 帧，ffprobe 复读为 1920 × 866 的 RGBA PNG。另验证了横屏 H.264 播放至结尾、竖屏编辑取消，以及自动验收中的候选保留、VFR 定位、前后五帧、PTS 回读、空白格和视频信息叠加。
- **授权实拍**。`train.mov` 来自 Immich 测试素材，维护者声明素材为公有领域。原片 SHA-256 为 `41CC5F00B7318627F83A67EF8BE08ACA65A26E6D39D265A6079717E520D6E096`。ffprobe 读到 iPhone 12 Pro、HEVC、HLG、1920 × 1080、21.738 s、显示矩阵 −90° 和 1,229 张源帧。时间基 `1/600` 下，相邻帧有 4 种间隔，范围 10 至 21 tick。选中的 9 张画面与按原帧序号独立解码的 BGR 像素逐字节一致。素材及其分镜保存在忽略目录中。[原始素材](https://github.com/immich-app/test-assets/blob/main/videos/train.mov) · [Immich 素材声明](https://github.com/immich-app/test-assets#test-assets-for-immich)
- **授权实拍在新版手动选帧中的表现**。主窗口生成竖屏九宫格，手动窗口正确显示竖屏预览和六列候选。逐帧从 `00:00:01.168` 前进到 `00:00:01.185`，与 ffprobe 的相邻 PTS `701`、`711` 一致。取消一张后智能补选从 `8 / 9` 恢复到 `9 / 9`，换一批后候选变化且计数为 `0 / 9`，取消编辑后原分镜仍有 9 张画面。本机 WPF 系统播放器无法连续播放这个 HEVC 文件，FFmpeg 取帧与选帧可用。

### 主窗口 Mac 样式验收

- 对照 Mac 实机截图与 `StudioLayout.swift`，队列栏 190、设置栏 216、工具栏 48、预览栏头 40、结果底栏 48、分页器 152 × 36，数值为逻辑点。复用 ShotMap 矢量标志和 Tabler Outline 图形，按对应字号、圆角、留白和选中态实现。实机检查了空队列、生成中、专注预览和恢复三栏。Windows 使用原生标题栏、系统字体、文件对话框和资源管理器。生成的分镜在工作区内预览，另存与批量导出由用户触发。[Mac 主窗口](https://github.com/ixiehao/ShotMap/blob/5ac4516e474f3ed20ca345e4198481ea67449886/website/assets/workspace-zh.webp) · [Mac 设置面板](https://github.com/ixiehao/ShotMap/blob/5ac4516e474f3ed20ca345e4198481ea67449886/website/assets/tutorials/layout-zh.webp)
- 从成品窗口一次导入授权 iPhone HEVC 实拍和横屏 VFR 两段素材。第一段以 3 × 3、1920 px 方形完成，随后批次暂停。切换到 4 × 4、2560 px、深海军蓝，开启视频信息，再继续。第二段得到 16 张画面，第一段仍为 9 张。通过底栏翻页并打开手动选帧，编辑器显示 `16 / 16`。
- 批量导出两份 WebP，ffprobe 读到 1920 × 1919、2560 × 2559。从另存为窗口把第二张从 WebP 切换成 PNG，扩展名同步更新。第二张 WebP 和 PNG 解码后的 BGRA SHA-256 一致。实拍文件 SHA-256 与原授权样本一致。
- 新版窗口实测停止正在生成的批次，已导出的文件和已有预览仍可用。拖放验收入口从同一窗口发起实际 Windows `FileDrop`，返回 `Copy`。自动回归通过 VFR PTS 与像素、旋转、HEVC、参数、手动选帧、取消后 FFmpeg 退出、拒写和重试。

## 实现与边界

取帧通过 `-copyts` 和 `showinfo` 记录选中流的实际 PTS、原始时间基以及自动旋转后的尺寸。自动候选采样按网格容量使用 96 至 256 张预算，分析图长边最多 320 px。手动概览保留已选画面并按时间抽取候选。拖动定位和前后逐帧使用 FFmpeg 读取实际帧时间戳。两条流程均按整数 PTS 回读并核对画面。分镜上的时间码显示相对起点的整秒，手动定位框显示毫秒。解码、评分、渲染与写入在后台执行，关闭窗口会取消并等待任务结束。

手动选帧的浅色界面以 Mac 版简体中文截图与仓库中的 Swift 源码为基准。播放／暂停使用同一套 Tabler 图形，按钮尺寸、数字字号、圆角、间距和选中态按对应控件实现。标题栏与中西文字形由 Windows 提供。

队列预览缓存使用会话临时目录，已保留分镜的预算为 1 GiB。界面一次加载一张缩小的预览，导出读取对应的完整分镜。媒体工具以绝对路径和参数列表启动，交互输入关闭，FFmpeg 输入协议限制为 `file`。导出先在目标目录写临时文件，检查取消后提交，需要覆盖已有文件时由「另存为」确认。

待验证从资源管理器直接拖入发布窗口、其他系统解码器下的 HEVC 连续播放、HDR 色彩映射、超长和 4K 素材的耗时与内存、不同 DPI 和高对比度。当前质量阈值用合成素材初步校准，真实夜景、轻微运动、动态尺寸、非标准旋转矩阵和其他封装需要进一步验证。安装包属于后续阶段。
