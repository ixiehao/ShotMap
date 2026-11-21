export const tutorialCopy = {
  en: {
    title: "ShotMap tutorials",
    home: "ShotMap home",
    language: "Tutorial language",
    intro: "Make your first storyboard, replace a frame, or change the layout for sharing.",
    sample: "Download Color Trail.mp4",
    setup: "The examples use ShotMap 0.2.20 on macOS 13 or later and Color Trail.mp4, a 36-second, 960 × 540 sample video. Put the video in a folder where you can save files.",
    verification: "Check the result",
    result: "Download the finished image",
    related: "More tutorials",
    openImage: "View screenshot at full size",
    guides: {
      "video-to-storyboard": {
        title: "Turn an MP4 into a 3 × 3 storyboard on Mac",
        summary: "Automatically pick nine frames from one video and save them as a single JPG.",
        steps: [
          "Drag Color Trail.mp4 into the video queue. You can also use the + button in the queue header.",
          "In **Storyboard Settings**, select **3 × 3**, **Match video**, **1,920 px** and **JPG**. Keep the ivory background and turn on **Show timestamps**. Leave the filename and video info switches off.",
          "Click **Create storyboard**. Wait for the queue entry to show **Saved** and for all nine frames to appear in the preview."
        ],
        alt: "English ShotMap workspace showing a saved three-by-three storyboard and JPG selected",
        caption: "The queue shows Saved. On the right, 3 × 3 and JPG are selected.",
        check: "Click **Show in Finder** above the preview. Open the JPG beside Color Trail.mp4 and check that it contains nine tiles with timecodes."
      },
      "choose-frames": {
        title: "Choose and replace frames in a ShotMap storyboard",
        summary: "Find a moment on the timeline, pick it yourself and fill the remaining slots automatically.",
        steps: [
          "Create the 3 × 3 JPG from Color Trail.mp4, select its preview and open **Select frames** at the bottom right.",
          "Enter **00:00:13.250** in the timeline time field and press Return. Use the −1 or +1 controls to inspect neighboring frames if needed.",
          "Use **Add frame** beneath the timeline. Click the resulting frame card to select it. A numbered badge identifies the selection, and its number also appears on the timeline.",
          "Click **Smart select** to fill the other eight slots while keeping your pick. Confirm **9 / 9**, then click **Save**."
        ],
        alt: "English manual editor with Color Trail at 13.250 seconds, nine selected frames and a numbered timeline",
        caption: "Nine frames are selected. Frame 5 carries the Manual badge and also appears on the timeline.",
        check: "Check the updated storyboard preview for the chosen scene, then use **Show in Finder** to open the new JPG. The JPEG made before the edit stays beside the video."
      },
      "layout-and-export": {
        title: "Make a square WebP storyboard with video details",
        summary: "Set a 1:1 layout, keep the timecodes and add the source video’s details.",
        steps: [
          "Add Color Trail.mp4 to the queue. In **Storyboard Settings**, choose **3 × 3**, **Square 1:1** and **1,920 px**.",
          "Choose the navy swatch, keep **Show timestamps** on and turn on **Show video info**. The info block includes the filename, so leave the separate filename switch off.",
          "Select **WebP** under **Export** and click **Create storyboard**. Use **Show in Finder** when the preview is ready."
        ],
        alt: "English workspace showing a square storyboard with a navy background and WebP selected",
        caption: "The square layout includes source details above the nine tiles. WebP is selected under Export.",
        check: "Use Finder’s Get Info to confirm the .webp extension, and open the image in Preview. In this example, the 1:1 preset produced a 1920 × 1919 px image. Look for timecodes on the tiles and the source details at the upper left."
      }
    }
  },
  zh: {
    title: "ShotMap 图文教程",
    home: "ShotMap 首页",
    language: "教程语言",
    intro: "从视频生成第一张分镜图，手动选帧，或调整画面比例与导出格式。",
    sample: "下载示例视频 Color Trail.mp4",
    setup: "示例使用 macOS 13 或更高版本上的 ShotMap 0.2.20，以及一段 36 秒、960 × 540 的 Color Trail.mp4。请把视频放在有写入权限的文件夹中。",
    verification: "核对成品",
    result: "下载示例成品",
    related: "更多教程",
    openImage: "查看原尺寸截图",
    guides: {
      "video-to-storyboard": {
        title: "在 Mac 上将 MP4 生成 3 × 3 分镜图",
        summary: "从一段视频自动选取九帧，拼成一张 JPG。",
        steps: [
          "把 Color Trail.mp4 拖入视频队列，也可以点击队列标题旁的 + 按钮添加。",
          "在**分镜设置**中选择 **3 × 3**、**随视频**、**1920 px** 和 **JPG**。保留米白色底色，开启**显示时间码**，关闭文件名和视频信息开关。",
          "点击**生成分镜图**。等队列状态显示**已保存**，确认预览中出现九张画面。"
        ],
        alt: "简体中文 ShotMap 主界面显示已保存的九宫格分镜图，右侧选中 JPG",
        caption: "队列显示「已保存」。右侧选中 3 × 3 和 JPG。",
        check: "点击预览上方的**在 Finder 中显示**。打开 Color Trail.mp4 同目录下的 JPG，确认九张画面带有时间码。"
      },
      "choose-frames": {
        title: "在 ShotMap 中手动选帧并替换分镜画面",
        summary: "用时间轴定位想要的瞬间，手动保留一帧，再自动补齐剩余位置。",
        steps: [
          "先用 Color Trail.mp4 生成 3 × 3 的 JPG。在主界面选中该分镜图，点击右下角的**手动选帧**。",
          "在时间框输入 **00:00:13.250**，按回车定位。需要查看前后相邻画面时，用 −1 或 +1 逐帧微调。",
          "点击时间轴下方的**添加当前帧**，再点击该帧的候选卡片完成选中。卡片和时间轴上会出现对应的数字标记。",
          "点击**智能选帧**补齐其余八帧。核对计数为 **9 / 9**，点击**保存**。"
        ],
        alt: "简体中文手动选帧窗口定位在 13.250 秒，已选九帧，时间轴显示编号标记",
        caption: "九帧已选满。第 5 帧带有「手动」标记，在时间轴上也能找到。",
        check: "回到分镜预览确认选中的画面已出现，再通过**在 Finder 中显示**打开新 JPG。手动选帧前生成的 JPG 仍在视频同目录。"
      },
      "layout-and-export": {
        title: "导出带视频信息的方形 WebP 分镜图",
        summary: "将分镜图设为 1:1，保留时间码并加入源视频信息。",
        steps: [
          "将 Color Trail.mp4 加入队列，在**分镜设置**中选择 **3 × 3**、**方形 1:1** 和 **1920 px**。",
          "选择深蓝色底色，保留**显示时间码**，开启**显示视频信息**。信息区已包含文件名，单独的文件名开关可以保持关闭。",
          "在**导出**中选择 **WebP**，点击**生成分镜图**。生成后点击**在 Finder 中显示**。"
        ],
        alt: "简体中文主界面显示深蓝色底的方形分镜图，导出选中 WebP",
        caption: "九张画面上方显示源视频信息，右侧导出选项为 WebP。",
        check: "在 Finder 的「显示简介」中确认扩展名为 .webp，再用「预览」打开图片。本例的 1:1 预设实际导出为 1920 × 1919 px。核对每帧的时间码和左上角的视频信息。"
      }
    }
  },
  ja: {
    title: "ShotMap の使い方",
    home: "ShotMap ホーム",
    language: "ガイドの言語",
    intro: "動画から絵コンテを作り、使いたいコマの選択や書き出し設定を試せます。",
    sample: "サンプル動画 Color Trail.mp4 をダウンロード",
    setup: "このガイドでは macOS 13 以降で ShotMap 0.2.20 と、36 秒・960 × 540 のサンプル動画 Color Trail.mp4 を使います。動画をファイルの保存が可能なフォルダに置いてください。",
    verification: "書き出した画像を確認",
    result: "作成例をダウンロード",
    related: "ほかのガイド",
    openImage: "原寸のスクリーンショットを表示",
    guides: {
      "video-to-storyboard": {
        title: "Mac で MP4 から 3 × 3 の絵コンテを作る",
        summary: "動画から 9 コマを自動で選び、1 枚の JPG にまとめます。",
        steps: [
          "Color Trail.mp4 を動画のキューにドラッグします。キューの見出し横にある + ボタンからも追加できます。",
          "**絵コンテ設定**で **3 × 3**、**動画に合わせる**、**1920 px**、**JPG** を選びます。アイボリーの背景色とタイムコード表示を使い、ファイル名と動画情報の表示はオフにします。",
          "**絵コンテを作成**をクリックします。キューに**保存済み**と表示され、プレビューに 9 コマが並ぶまで待ちます。"
        ],
        alt: "日本語の ShotMap メイン画面。保存済みの 3 × 3 の絵コンテと選択中の JPG ボタン",
        caption: "キューに「保存済み」と表示され、右側で 3 × 3 と JPG が選ばれています。",
        check: "プレビュー上部の**Finder に表示**をクリックします。Color Trail.mp4 と同じフォルダにある JPG を開き、9 コマとタイムコードを確認します。"
      },
      "choose-frames": {
        title: "ShotMap の絵コンテで使うコマを手動で選ぶ",
        summary: "タイムラインで使いたいコマを見つけ、残りのマスを自動選択で埋めます。",
        steps: [
          "Color Trail.mp4 で 3 × 3 の JPG を作ります。プレビューを選び、右下の**コマを選ぶ**をクリックします。",
          "タイムコード欄に **00:00:13.250** と入力して Return キーを押します。前後のコマを確認するときは −1 または +1 を使います。",
          "タイムラインの下にある**フレームを追加**をクリックし、追加された候補を選びます。候補とタイムラインに番号が表示されます。",
          "**自動選択**をクリックすると、選んだコマを残したまま残り 8 コマが埋まります。**9 / 9** を確認して**保存**をクリックします。"
        ],
        alt: "日本語の手動選択画面。時刻は 13.250 秒で、9 コマの選択番号がタイムラインに表示されている",
        caption: "9 コマを選択済みです。「手動」マークの付いた 5 番はタイムラインにも表示されます。",
        check: "プレビューで選んだ場面を確認してから、**Finder に表示**で新しい JPG を開きます。編集前の JPG は動画と同じフォルダに残ります。"
      },
      "layout-and-export": {
        title: "動画情報付きの正方形の絵コンテを WebP で書き出す",
        summary: "1:1 のレイアウトで、タイムコードと元の動画情報を表示します。",
        steps: [
          "Color Trail.mp4 をキューに追加し、**絵コンテ設定**で **3 × 3**、**正方形 1:1**、**1920 px** を選びます。",
          "紺色の背景を選び、タイムコード表示をオンのまま、**動画情報を表示**をオンにします。動画情報にファイル名が含まれるため、ファイル名の表示はオフのままで構いません。",
          "**書き出し**で **WebP** を選び、**絵コンテを作成**をクリックします。作成後に**Finder に表示**をクリックします。"
        ],
        alt: "日本語のメイン画面。紺色の正方形の絵コンテが表示され、WebP が選択されている",
        caption: "9 コマの上に元の動画情報があり、右側の書き出し設定で WebP が選ばれています。",
        check: "Finder の「情報を見る」で拡張子が .webp であることを確認します。この例で 1:1 の設定から書き出された画像は 1920 × 1919 px です。「プレビュー」で各コマのタイムコードと左上の動画情報を確認します。"
      }
    }
  }
};
