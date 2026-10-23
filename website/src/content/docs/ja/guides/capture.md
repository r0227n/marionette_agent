---
title: 画像と動画を残す
description: スクリーンショット・注釈・録画を使って、操作後の状態を記録する。
---

画面を保存すると、CLIの応答と実際の表示を照合できます。保存先の親ディレクトリは先に作り、各実行で新しいファイル名を使います。

## スクリーンショット

```sh
mkdir -p artifacts
marionette-agent screenshot artifacts/after.png
marionette-agent screenshot artifacts/after.jpg --screenshot-format jpeg
```

既定はPNGです。JPEGは`--screenshot-format jpeg`を明示し、品質を変える場合は`--screenshot-quality`を0〜100で指定します。拡張子だけで形式は切り替わりません。JPEGの透過部分は白背景へ合成されます。

pathを省略すると、専用の一時ディレクトリへ保存してパスを返します。`--screenshot-dir`で既存ディレクトリを指定することもできます。既存ファイルを上書きしません。

## iOSのダイアログとキーボードを含める

既定の`--source flutter`はFlutter描画を撮影し、従来のtester workflowも維持します。OS UIを含めるには`ios-simulator`を選び、`SIMULATOR_UDID`に既定device set内で起動済みのiOS Simulatorの正確なUDIDを設定してください。名前や`booted`は1台だけ起動していても拒否します。完全なXcodeを選択したmacOSが必要ですが、この撮影にはアプリ接続やMarionette bindingは不要です。

```sh
marionette-agent screenshot artifacts/os-ui.png \
  --source ios-simulator --device "$SIMULATOR_UDID" --json
marionette-agent screenshot artifacts/os-ui.jpg \
  --source ios-simulator --device "$SIMULATOR_UDID" --screenshot-format jpeg
```

保存画像には、対象端末に表示中の権限ダイアログ、写真ピッカー、ソフトウェアキーボード、ステータスバー、セーフエリアが入ります。internal framebufferを全解像度で取得し、ノッチ・角丸mask、端末外枠、Macウィンドウ装飾は含めません。Macのウィンドウ倍率には影響されません。回転完了後に取得し、`capture.pixelWidth/pixelHeight`で保存寸法を確認してください。`capture.orientation`は寸法の縦横比（portrait/landscape/square）で、センサー角度ではありません。検証したiPhone 17 Pro / iOS 26.2では、横向きUIも1206×2622の縦長framebufferで返ります。画像は自動回転しません。取得元、UDID、runtime、display、撮影範囲、mask、物理pixel座標系も結果に含みます。

sessionが別アプリに接続していても、指定UDIDが撮影対象です。ダミー写真を入れた専用Simulatorを使い、共有前に画像を確認してください。保護・制限された内容は取得を保証せず、CLIによる権限変更、ダイアログの消去、制限回避は行いません。撮影失敗をFlutter画像で代替しません。形式、品質、保存先選択、排他的作成、元のtimeoutは上記と共通です。

native画像ではFlutter ref注釈、対象crop、`diff screenshot`を使えません。座標契約が異なるため、nativeの注釈・cropは明示的なエラーになります。MCP screenshotでも同じ`source`と`device`を指定できます。workflowのscreenshot stepも同じ経路を使います。[workflowのstep](/marionette_agent/ja/guides/workflows/)を参照してください。

iOS実機は**非対応**です。`--source ios-device --device <id>`は`UNSUPPORTED_CAPABILITY`を返します。実機には別途署名済みXCTest runner、pairing・信頼、Developer Mode、互換OS/Xcode環境が必要であり、simctlはSimulator専用です。[取得契約と実現性調査](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/SPEC.ja.md#native-ios-screenshots)を参照してください。

## refを画像へ重ねる

```sh
marionette-agent snapshot
marionette-agent screenshot --annotate artifacts/targets.png
```

注釈には直近の有効snapshotとmapped screenshot providerが必要です。exampleは対応しています。途中でUI操作をした場合は、snapshotを取り直します。画像上の番号と操作対象を照合する用途に使います。

## Flutterアプリの描画を録画する

接続済みsessionと、ネイティブライブラリを同梱したCLI一式を用意します。Flutter描画の録画は、headlessの環境でも同じ構文です。

```sh
marionette-agent record start artifacts/interaction.mp4 --platform flutter
marionette-agent tap --key tap_button
marionette-agent snapshot
marionette-agent record status
marionette-agent record stop
```

単一のFlutter viewを無音H.264動画として保存します。`--fps`は取得間隔を指定し、既定は10です。実際の取得時刻を使うため固定フレームレートの保証はありません。OSのキーボード・ダイアログ・ブラウザーUI・platform viewまで記録されるとは限りません。

## 端末画面を録画する

iOS Simulatorの画面全体を記録する場合は、対象のUDIDをこのシェルの`SIMULATOR_UDID`へ設定します。VM Service接続は不要です。

```sh
marionette-agent record start artifacts/device.mp4 \
  --platform ios --device "$SIMULATOR_UDID"
marionette-agent record stop
```

Androidは端末serial、macOSはディスプレイ番号を指定します。Webは`display:1@ws://127.0.0.1:9222/devtools/page/ACTUALID`のように、display番号と選んだChrome pageのloopback debugging WebSocket URLを組み合わせます。設定と制限は[Webの指定契約](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/cli-reference.ja.md#web-recording)を参照してください。macOS・Webの画面収録にはOSの許可が必要です。Web方式は指定ディスプレイを記録するため、ブラウザーのページ領域だけに限定されません。

`record restart`は現在の録画を確定してから別の保存先で再開します。新規開始が失敗しても、以前の録画へ戻るわけではありません。`stop`は動画の確定まで待つため、長い録画には十分なtimeoutを指定してください。

[画像・録画の詳細](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/cli-reference.ja.md#capture)に命名・排他保存・期限・確定・復旧の条件をまとめています。
