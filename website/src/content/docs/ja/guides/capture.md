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

## AndroidのOS標準UIを撮影する

既定のスクリーンショットはtesterを含むFlutter描画のままです。Androidを明示すると、権限ダイアログ、Photo Picker・ファイル選択、ソフトウェアキーボード、表示中のsystem barを含めて撮影できます。Android Emulatorを起動し、オンラインかつ認証済みのADB serialを`ANDROID_SERIAL`に設定してください。単独のネイティブ撮影にはMarionette接続は不要です。

```sh
marionette-agent screenshot artifacts/system.png --platform android --device "$ANDROID_SERIAL" --json
marionette-agent screenshot artifacts/system.jpg --platform android --device "$ANDROID_SERIAL" --screenshot-format jpeg
```

結果には`capture.source`、`device`、`display`、`scope`、`coordinateSpace`、`width`、`height`を含みます。寸法は撮影時の向きのpixel数で、densityによる拡縮はしません。OS標準UIを開いたまま撮影してください。撮影処理はダイアログを閉じず、UI操作を再送しません。

この版の対応対象はEmulatorの既定display `0`だけです。実機と複数displayは拒否します。接続端末が1台でも`--device`は必須です。ADB取得の失敗時にFlutterへ切り替えません。ネイティブ画像ではFlutterのref・selector・`--annotate`・crop・`diff screenshot`を利用できず、これらは従来のFlutter向けの動作を保ちます。

Androidは`FLAG_SECURE`対象を隠したり撮影を拒否したりします。黒い領域だけで保護の有無を確定できないため、取得成功時は`protectedContent: "not-detectable"`を返します。保護やデバッグ認証は回避しません。ダミーデータで検証し、画面全体の画像を共有する前に無関係な情報の写り込みを確認してください。エラーと制限は[ネイティブ撮影契約](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/cli-reference.ja.md#native-android-capture)を参照してください。

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
