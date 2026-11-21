# 在 ShotMap 中手动选帧并替换分镜画面 · ShotMap

> 用时间轴定位想要的瞬间，手动保留一帧，再自动补齐剩余位置。

<https://ixiehao.github.io/ShotMap/zh/tutorials/choose-frames/>

[ShotMap 图文教程](https://ixiehao.github.io/ShotMap/zh/#tutorials)

## 在 ShotMap 中手动选帧并替换分镜画面

用时间轴定位想要的瞬间，手动保留一帧，再自动补齐剩余位置。

示例使用 macOS 13 或更高版本上的 ShotMap 0.2.20，以及一段 36 秒、960 × 540 的 Color Trail.mp4。请把视频放在有写入权限的文件夹中。

[下载示例视频 Color Trail.mp4](https://ixiehao.github.io/ShotMap/assets/tutorials/Color%20Trail.mp4)

1. 先用 Color Trail.mp4 生成 3 × 3 的 JPG。在主界面选中该分镜图，点击右下角的 **手动选帧** 。

2. 在时间框输入 **00:00:13.250** ，按回车定位。需要查看前后相邻画面时，用 −1 或 +1 逐帧微调。

3. 点击时间轴下方的 **添加当前帧** ，再点击该帧的候选卡片完成选中。卡片和时间轴上会出现对应的数字标记。

4. 点击 **智能选帧** 补齐其余八帧。核对计数为 **9 / 9** ，点击 **保存** 。

[简体中文手动选帧窗口定位在 13.250 秒，已选九帧，时间轴显示编号标记](https://ixiehao.github.io/ShotMap/assets/tutorials/frames-zh.webp)

九帧已选满。第 5 帧带有「手动」标记，在时间轴上也能找到。 [查看原尺寸截图](https://ixiehao.github.io/ShotMap/assets/tutorials/frames-zh.webp)

### 核对成品

回到分镜预览确认选中的画面已出现，再通过 **在 Finder 中显示** 打开新 JPG。手动选帧前生成的 JPG 仍在视频同目录。

[下载示例成品](https://ixiehao.github.io/ShotMap/assets/tutorials/manual-storyboard.jpg)

### 更多教程

- [**在 Mac 上将 MP4 生成 3 × 3 分镜图** 从一段视频自动选取九帧，拼成一张 JPG。](https://ixiehao.github.io/ShotMap/zh/tutorials/video-to-storyboard/)

- [**导出带视频信息的方形 WebP 分镜图** 将分镜图设为 1:1，保留时间码并加入源视频信息。](https://ixiehao.github.io/ShotMap/zh/tutorials/layout-and-export/)
