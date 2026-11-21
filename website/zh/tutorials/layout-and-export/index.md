# 导出带视频信息的方形 WebP 分镜图 · ShotMap

> 将分镜图设为 1:1，保留时间码并加入源视频信息。

<https://ixiehao.github.io/ShotMap/zh/tutorials/layout-and-export/>

[ShotMap 图文教程](https://ixiehao.github.io/ShotMap/zh/#tutorials)

## 导出带视频信息的方形 WebP 分镜图

将分镜图设为 1:1，保留时间码并加入源视频信息。

示例使用 macOS 13 或更高版本上的 ShotMap 0.2.20，以及一段 36 秒、960 × 540 的 Color Trail.mp4。请把视频放在有写入权限的文件夹中。

[下载示例视频 Color Trail.mp4](https://ixiehao.github.io/ShotMap/assets/tutorials/Color%20Trail.mp4)

1. 将 Color Trail.mp4 加入队列，在 **分镜设置** 中选择 **3 × 3** 、 **方形 1:1** 和 **1920 px** 。

2. 选择深蓝色底色，保留 **显示时间码** ，开启 **显示视频信息** 。信息区已包含文件名，单独的文件名开关可以保持关闭。

3. 在 **导出** 中选择 **WebP** ，点击 **生成分镜图** 。生成后点击 **在 Finder 中显示** 。

[简体中文主界面显示深蓝色底的方形分镜图，导出选中 WebP](https://ixiehao.github.io/ShotMap/assets/tutorials/layout-zh.webp)

九张画面上方显示源视频信息，右侧导出选项为 WebP。 [查看原尺寸截图](https://ixiehao.github.io/ShotMap/assets/tutorials/layout-zh.webp)

### 核对成品

在 Finder 的「显示简介」中确认扩展名为 .webp，再用「预览」打开图片。本例的 1:1 预设实际导出为 1920 × 1919 px。核对每帧的时间码和左上角的视频信息。

[下载示例成品](https://ixiehao.github.io/ShotMap/assets/tutorials/square-storyboard.webp)

### 更多教程

- [**在 Mac 上将 MP4 生成 3 × 3 分镜图** 从一段视频自动选取九帧，拼成一张 JPG。](https://ixiehao.github.io/ShotMap/zh/tutorials/video-to-storyboard/)

- [**在 ShotMap 中手动选帧并替换分镜画面** 用时间轴定位想要的瞬间，手动保留一帧，再自动补齐剩余位置。](https://ixiehao.github.io/ShotMap/zh/tutorials/choose-frames/)
