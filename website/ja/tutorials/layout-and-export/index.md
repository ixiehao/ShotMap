# 動画情報付きの正方形の絵コンテを WebP で書き出す · ShotMap

> 1:1 のレイアウトで、タイムコードと元の動画情報を表示します。

<https://ixiehao.github.io/ShotMap/ja/tutorials/layout-and-export/>

[ShotMap の使い方](https://ixiehao.github.io/ShotMap/ja/#tutorials)

## 動画情報付きの正方形の絵コンテを WebP で書き出す

1:1 のレイアウトで、タイムコードと元の動画情報を表示します。

このガイドでは macOS 13 以降で ShotMap 0.2.20 と、36 秒・960 × 540 のサンプル動画 Color Trail.mp4 を使います。動画をファイルの保存が可能なフォルダに置いてください。

[サンプル動画 Color Trail.mp4 をダウンロード](https://ixiehao.github.io/ShotMap/assets/tutorials/Color%20Trail.mp4)

1. Color Trail.mp4 をキューに追加し、 **絵コンテ設定** で **3 × 3** 、 **正方形 1:1** 、 **1920 px** を選びます。

2. 紺色の背景を選び、タイムコード表示をオンのまま、 **動画情報を表示** をオンにします。動画情報にファイル名が含まれるため、ファイル名の表示はオフのままで構いません。

3. **書き出し** で **WebP** を選び、 **絵コンテを作成** をクリックします。作成後に **Finder に表示** をクリックします。

[日本語のメイン画面。紺色の正方形の絵コンテが表示され、WebP が選択されている](https://ixiehao.github.io/ShotMap/assets/tutorials/layout-ja.webp)

9 コマの上に元の動画情報があり、右側の書き出し設定で WebP が選ばれています。 [原寸のスクリーンショットを表示](https://ixiehao.github.io/ShotMap/assets/tutorials/layout-ja.webp)

### 書き出した画像を確認

Finder の「情報を見る」で拡張子が .webp であることを確認します。この例で 1:1 の設定から書き出された画像は 1920 × 1919 px です。「プレビュー」で各コマのタイムコードと左上の動画情報を確認します。

[作成例をダウンロード](https://ixiehao.github.io/ShotMap/assets/tutorials/square-storyboard.webp)

### ほかのガイド

- [**Mac で MP4 から 3 × 3 の絵コンテを作る** 動画から 9 コマを自動で選び、1 枚の JPG にまとめます。](https://ixiehao.github.io/ShotMap/ja/tutorials/video-to-storyboard/)

- [**ShotMap の絵コンテで使うコマを手動で選ぶ** タイムラインで使いたいコマを見つけ、残りのマスを自動選択で埋めます。](https://ixiehao.github.io/ShotMap/ja/tutorials/choose-frames/)
