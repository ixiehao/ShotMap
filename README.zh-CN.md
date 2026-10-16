# 视频一键拼图（ShotMap）

[![最新版本](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![自动验证](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![许可证：MIT](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

![ShotMap 中文工作区正在处理《Tears of Steel》并生成分镜图](docs/assets/readme-workspace-zh.png?v=tears-20261016)

## 打开视频前，内容一眼看懂

**视频一键拼图（ShotMap）** 会从视频中挑选有代表性的画面，整理成一张清晰的分镜图。先浏览这张图，就能大致知道视频讲了什么、按什么顺序发生；需要时再打开原片。它是一款原生 macOS 开源软件：无需账号、无需上传、没有云端队列。

智能选帧会先给出可靠的结果。某一帧不合适时，可在“手动选择画面”窗口中替换为你想要的准确画面。整个过程都在你的 Mac 上完成。

> **从这里开始：**[下载最新通用 DMG](https://github.com/ixiehao/ShotMap/releases/latest) · macOS 13 或更高版本 · 支持 Apple Silicon 与 Intel Mac

> **演示视频署名：**《Tears of Steel》（2012）© Blender Foundation / Blender Institute，采用 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) 许可。下方的软件截图和动图均使用该视频制作。

## 为那些想再次找到的视频而做

- **家庭与个人影像：**不用逐个打开文件，也能找到生日、旅行、日落或孩子成长的片段。
- **创作者与剪辑师：**在导入剪辑软件前，先快速浏览一批素材，找到真正需要的镜头。
- **整理视频文件夹：**为每段原片保存一张紧凑的视觉索引图；需要时还可显示时间码和文件名。

## 三步生成分镜图

| 1. 添加视频 | 2. 选择关键画面 | 3. 保存分镜图 |
| --- | --- | --- |
| 拖入一部视频，或一次加入多部。 | 先用智能选帧，再按需手动替换。 | 在原视频旁导出 PNG 或 JPG。 |

## 为快速找回画面而设计

- 默认选择清晰、有代表性的画面，尽量避开黑屏、模糊和近似重复的镜头。
- 手动选帧窗口把播放器、可视化时间轴、逐帧调整和候选画廊放在一起，替换画面更直接。
- 支持可见队列；分镜图会随着结果完成逐张填入预览。
- 可选择 3 × 3 至 8 × 8 网格、比例、底色、图片宽度，以及是否显示时间码和文件标题。
- 支持 MP4、MOV、MPEG 等当前 macOS 支持的视频格式。
- 支持 English、简体中文、日本語界面，以及浅色、深色或跟随系统外观。

### 看看真实操作

下方录屏来自真实软件：从已完成的分镜图进入手动选帧窗口，在可视化时间轴上定位画面，再从候选区选择更合适的一帧后保存。

![ShotMap 从 Tears of Steel 分镜工作区进入手动选帧窗口，展示可视化时间轴与候选画廊](docs/assets/video-to-storyboard-demo.gif?v=tears-20261016)

## 下载与安装

**大多数用户：**打开[最新版本页面](https://github.com/ixiehao/ShotMap/releases/latest)，下载通用 `.dmg`，再将 **ShotMap.app** 拖进“应用程序”文件夹。

版本页面附有 SHA-256 校验文件，供需要验证下载的用户使用。ShotMap 暂未经过 Apple 公证。若 macOS 提示无法验证开发者，请在“应用程序”中按住 Control 点按应用，选择“打开”，再确认一次“打开”。无需降低 macOS 的系统级安全设置。

## 隐私优先

视频始终保留在你的 Mac 上。ShotMap 不需要账号，没有跟踪或云上传，也不包含 Electron、FFmpeg 或 Python 运行时。可选的更新检查只读取 GitHub 公开版本信息，不会上传视频或使用数据。

## 帮助、反馈与社区

- **第一次使用？**访问[官网](https://ixiehao.github.io/ShotMap/)查看简洁的产品介绍与真实运行截图。
- **需要帮助、发现问题或有功能建议？**请先看[支持与反馈](SUPPORT.md)，可复现的问题和明确的功能建议请使用 [Issue 表单](https://github.com/ixiehao/ShotMap/issues/new/choose)。
- **想提问或分享经验？**欢迎加入 [GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions)。
- **想参与开发？**请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请通过私密的[漏洞报告通道](https://github.com/ixiehao/ShotMap/security/advisories/new)提交。
- **项目资料：**[CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [开发者：ixiehao](https://github.com/ixiehao)

## 权利与许可

- ShotMap 的 Swift 源码、文档和 Iris 图标均为本项目原创内容，按 [MIT License](LICENSE) 发布。
- 应用只使用 Apple SDK 框架；未包含第三方应用代码、依赖包、分析 SDK 或 MoviePrint 素材。
- 内置的 [Tabler Icons Outline](https://github.com/tabler/tabler-icons) SVG 保持原样，按 [MIT License](ThirdPartyLicenses/TablerIcons-MIT.txt) 使用；内置 Noto Sans CJK 字体采用 [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt)。详情见 [NOTICE.md](NOTICE.md)。
- 文档演示视频《Tears of Steel》（2012）© Blender Foundation / Blender Institute，采用 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) 许可。
- 请仅处理你拥有或获授权分析的视频。生成分镜图并不授予发布或再分发原视频的权限。
