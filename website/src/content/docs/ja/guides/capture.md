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

## refを画像へ重ねる

```sh
marionette-agent snapshot
marionette-agent screenshot --annotate artifacts/targets.png
```

注釈には直近の有効snapshotとmapped screenshot providerが必要です。exampleは対応しています。途中でUI操作をした場合は、snapshotを取り直します。画像上の番号と操作対象を照合する用途に使います。

## Flutterアプリの描画を録画する

接続済みsessionとffmpegを用意します。Flutter描画の録画は、headlessの環境でも同じ構文です。

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

Androidは端末serial、macOS・Webは録画対象のディスプレイ番号を指定します。macOS・Webの画面収録にはOSの許可が必要です。Web方式は指定ディスプレイを記録するため、ブラウザーのページ領域だけに限定されません。

`record restart`は現在の録画を確定してから別の保存先で再開します。新規開始が失敗しても、以前の録画へ戻るわけではありません。`stop`は動画の確定まで待つため、長い録画には十分なtimeoutを指定してください。
