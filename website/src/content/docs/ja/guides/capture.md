---
title: 画像と動画を残す
description: XCUIScreenでiOS標準UIを撮影し、アプリや端末の動画を残す。
---

画面を保存し、CLIの応答と実際の表示を照合します。スクリーンショットは、同梱のXCTest UI-test runnerからAppleの`XCUIScreen.main.screenshot()`で取得します。`SIMULATOR_UDID`に起動済みiOS Simulatorの正確なUDIDを設定してください。名前や`booted`は拒否します。完全なXcodeを選択したmacOSが必要です。アプリ接続、Marionette binding、アプリ側の画像providerは不要です。

## スクリーンショット

```sh
mkdir -p artifacts
marionette-agent --timeout 120000 screenshot artifacts/after.png --device "$SIMULATOR_UDID"
marionette-agent --timeout 120000 screenshot artifacts/after.jpg --device "$SIMULATOR_UDID" --screenshot-format jpeg
```

取得元の既定は`ios-simulator`です。初回撮影でCLI自身のrunnerをビルドし、daemonの存続中はそのbuildを再利用します。`--timeout`にはコンパイルとXCTest起動の時間を確保してください。同じ期限に画像回収・変換・保存も含まれます。対象アプリのXcode projectを編集する必要はありません。コンパイル済みCLIにも同じrunnerソースが含まれます。

PNGには表示中のOS権限ダイアログ、写真ピッカー、ソフトウェアキーボード、ステータスバー、セーフエリアが入ります。runnerは対象アプリの起動・前面化やUIのtapを行わず、main screenを観測します。sessionの接続先が別アプリでも、指定UDIDが撮影対象です。ダミーデータの専用Simulatorを使い、共有する画像を目視確認してください。

結果の`capture`には`method: xcuiscreen`、取得元、端末UDID、runtime、`display: main`、`scope: device-screen`、`mask: system-default`、物理pixel寸法と画像の向きが入ります。ノッチ・角丸maskを指定するAPIは使わず、XCUIScreenのシステム画像をそのまま取得します。Macのウィンドウ装飾や倍率は影響しません。回転完了後に取得し、保存PNGと返された寸法を照合してください。`orientation`は画像の縦横比であり、センサーの向きではありません。CLIは画像を回転・resizeしません。横向きのXCUIScreen PNGが縦長の画素配列とEXIFの向き情報を持つ場合があり、JPEGでもその向き情報を保持します。

既定形式はPNGです。JPEGは`--screenshot-format jpeg`で明示し、品質は`--screenshot-quality`で0〜100を指定します。拡張子だけで形式は変わりません。JPEGは透過を白へ合成します。pathを省略すると非公開の一時出力を返し、既存directoryは`--screenshot-dir`で指定できます。親directoryは事前作成が必要で、既存fileは上書きしません。

## AndroidのOS標準UIを撮影する

`--source android-emulator`を選び、私有pairingファイルのpathを`CAPTURE_PAIRING`へ設定します。[撮影agentの準備](https://github.com/r0227n/marionette_agent/blob/develop/packages/marionette_agent_android/capture_agent/README.md)に従ってpairingを作成し、Android StudioまたはGradleでInstrumentationを起動したままにします。この別の準備環境はAndroid debugging transportを内部利用します。撮影コマンドは認証付きローカルTCPからUI Automatorを呼び、ADBコマンドを実行しません。Flutter接続は不要です。

```sh
marionette-agent screenshot artifacts/android.png --source android-emulator --device "$CAPTURE_PAIRING"
marionette-agent screenshot artifacts/android.jpg --source android-emulator --device "$CAPTURE_PAIRING" --screenshot-format jpeg
```

単一display 0のEmulatorだけを対象とします。結果は`method: uiautomator`となり、既存のPNG/JPEG・排他的保存・物理pixel metadataを使います。権限ダイアログ・写真／ファイルpicker・IME・system barを含み、回転後のdisplay pixelを取得します。FLAG_SECUREの対象が隠れるかエラーになる場合があり、黒pixelだけでは保護を確定しません。失敗時にFlutterや別の取得元へ切り替えません。MCP・workflowでも`source: android-emulator`とpairingファイルの`device`を使えます。既定のiOS撮影は維持します。

## 既存の撮影コマンドから移行する

Marionette/Flutter経由の静止画、ref/selectorによるcrop、`--annotate`、exampleのmapped providerは削除しました。すべての撮影にdeviceが必要です。静止画の対応対象はiOS Simulatorです。Flutter testerなどのアプリ環境では[Flutter描画の録画](#flutterアプリの描画を録画する)を使えます。

MCP screenshotは`device`が必須で、任意の`source`は既定`ios-simulator`です。workflowのscreenshot stepも同じ経路で、`device`にUDID文字列が必要です。撮影だけのworkflowには接続が不要です。[workflow step](/marionette_agent/ja/guides/workflows/)を参照してください。

```sh
marionette-agent --timeout 120000 diff screenshot --device "$SIMULATOR_UDID" --baseline artifacts/after.png --output artifacts/difference.png
```

画像diffも新しいXCUIScreen画像を取得します。同じ端末・取得方式・回転後の向きで撮ったPNGをbaselineにしてください。寸法の一致が必要です。thresholdは物理pixelを比較し、Flutter refの座標へ変換しません。

この実装ではiOS実機は引き続き非対応です。`--source ios-device --device <id>`は`UNSUPPORTED_CAPABILITY`です。署名・provisioningと実機runnerの寿命管理は実装・検証していません。保護・制限された内容の取得は保証しません。失敗時に取得元を切り替えたり、ダイアログを閉じたり、アプリ操作を再送したりしません。[撮影契約](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/SPEC.ja.md#native-ios-screenshots)を参照してください。

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
