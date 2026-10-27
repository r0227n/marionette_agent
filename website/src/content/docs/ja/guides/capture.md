---
title: 画像と動画を残す
description: スクリーンショット・注釈・録画を使って、操作後の状態を記録する。
---

スクリーンショットはAndroid Emulator上のUI Automator APIで取得します。単独撮影にMarionette接続は不要です。Flutter撮影、ref注釈、要素cropは廃止しました。

## 撮影agentを起動する

`tool/android_capture.dart`で私有pairingファイルを作成し、Android StudioまたはGradleから別のAndroid Instrumentationを起動します。SDK要件と手順は[agentのセットアップ](https://github.com/r0227n/marionette_agent/blob/develop/packages/marionette_agent_android/capture_agent/README.md)を参照してください。撮影中はagentを起動したままにし、私有ファイルのpathを`CAPTURE_PAIRING`へ設定します。

撮影コマンドはADBコマンドを実行せず、認証付きローカルTCPでPNGを受け取ります。最初のAPK配備とInstrumentation起動はAndroidのテスト実行環境で行います。Emulatorごとにpairing名とportを分離してください。

## 画面を保存する

```sh
marionette-agent screenshot artifacts/system.png --device "$CAPTURE_PAIRING" --json
marionette-agent screenshot artifacts/system.jpg --device "$CAPTURE_PAIRING" --screenshot-format jpeg
```

既定はPNGです。JPEGは`--screenshot-quality 0..100`に対応し、既定90です。親ディレクトリを先に作成してください。path省略時は`--screenshot-dir`または私有一時ディレクトリを使います。既存ファイルは上書きしません。

結果は`capture.source: "android-uiautomator"`、pairingした`device`名、display `0`、`scope: "entire-display"`、`coordinateSpace: "physical-pixels"`、デコードした`width`/`height`を含みます。回転後のdisplay pixelをdensityで拡縮せず取得します。権限ダイアログ、Photo Picker・ファイル選択、IME、表示中のsystem barを含みます。確認対象のUIを開いたまま撮影してください。

display 0だけのEmulatorに対応します。`--device`は必ずpairingファイルを指定し、相対pathは呼出元CLIのcwd基準です。探索、別端末選択、fallbackはありません。認証失敗、agent切断、破損応答、期限超過はエラーになります。

Androidは`FLAG_SECURE`対象を隠したり撮影を拒否したりします。成功時は`protectedContent: "not-detectable"`を返し、黒pixelだけで保護を確定しません。ダミーデータを使い、共有前に画面全体の写り込みを確認してください。

## Pixelを比較する

```sh
marionette-agent diff screenshot --baseline artifacts/system.png --device "$CAPTURE_PAIRING" --output artifacts/diff.png
```

同じ端末・display設定のPNGをbaselineに指定してください。画像のpixel寸法が一致する必要があります。ref・selectorのcropと`--annotate`は利用できません。制限は[撮影契約](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/cli-reference.ja.md#native-android-capture)を参照してください。

## 遷移を録画する

端末のネイティブ録画は静止画撮影とは別機能です。iOS Simulatorの例:

```sh
marionette-agent record start artifacts/interaction.mp4 --platform ios --device "$IOS_UDID"
marionette-agent record stop
```

Marionette・Flutterフレーム録画も廃止しました。環境に対応するネイティブ録画platformを利用してください。
