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

Marionette/Flutter経由の静止画、ref/selectorによるcrop、`--annotate`、exampleのmapped providerは削除しました。すべての撮影にdeviceが必要です。静止画の対応対象はiOS SimulatorとAndroid Emulatorです。Flutter tester描画の録画は利用できません。

MCP screenshotは`device`が必須で、任意の`source`は既定`ios-simulator`です。workflowのscreenshot stepも同じ経路で、`device`にはiOSのUDIDまたはAndroidのpairingファイルを指定します。撮影だけのworkflowには接続が不要です。[workflow step](/marionette_agent/ja/guides/workflows/)を参照してください。

```sh
marionette-agent --timeout 120000 diff screenshot --device "$SIMULATOR_UDID" --baseline artifacts/after.png --output artifacts/difference.png
```

画像diffも選択した取得元から新しい画像を取得します。同じ端末・取得方式・回転後の向きで撮ったPNGをbaselineにしてください。寸法の一致が必要です。thresholdは物理pixelを比較し、Flutter refの座標へ変換しません。

この実装ではiOS実機は引き続き非対応です。`--source ios-device --device <id>`は`UNSUPPORTED_CAPABILITY`です。署名・provisioningと実機runnerの寿命管理は実装・検証していません。保護・制限された内容の取得は保証しません。失敗時に取得元を切り替えたり、ダイアログを閉じたり、アプリ操作を再送したりしません。[撮影契約](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/SPEC.ja.md#native-ios-screenshots)を参照してください。

## プラットフォームAPIによる録画

録画はMarionetteやVM Service接続を使いません。`--platform flutter`と録画専用接続を削除しました。取得失敗時にFlutterへフォールバックしません。ホストは同梱native動画ライブラリを利用できるmacOSです。

| platform | device                                     | 取得方法と出力                                                                                  |
| -------- | ------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| ios      | 起動済みSimulatorのUDID                    | 同梱の常駐XCTest runnerが`XCUIScreen.main.screenshot()`を呼ぶ。H.264 MP4                        |
| android  | 非公開のUI Automatorペアリングファイル     | 既存のcapture instrumentationが`UiDevice.takeScreenshot`を呼ぶ。Emulatorのdisplay 0。H.264 MP4  |
| macos    | 1始まりのactive display番号                | ScreenCaptureKitの`SCStream`と`SCRecordingOutput`。macOS 15以上・Xcode・画面収録許可。H.264 MOV |
| web      | `ws://127.0.0.1:<port>/devtools/page/<ID>` | Chromium CDPの`Page.captureScreenshot`。headlessを含むpage viewport。H.264 MP4                  |

platform・device・新規出力pathを必須とします。相対pathとAndroidのペアリングpathは呼出元cwd基準です。既存file・directory・symlinkを拒否します。録画はsessionを所有し、同一daemonの明示対象を終了確認まで予約します。Web pageはmacOS displayを予約しません。Android instrumentationはスクリーンショットと同じ手順で別途起動し、録画停止では終了させません。iOSはrunnerをbuild・所有しますが、観測対象アプリを起動しません。端末一覧とrunnerの後処理にsimctlを使う場合がありますが、画像・動画取得には使いません。adb screenrecordとscreencaptureによる録画も削除しています。

iOS/Android/WebはプラットフォームAPIからPNGを連続取得し、単調時計による実取得時刻でVFR動画へ変換します。native動画streamのfpsを保証する方式ではありません。`--fps 1..60`は取得後の待機間隔（既定10）で、取得・転送時間が加わり、高速アニメーションを取りこぼす場合があります。録画時間に応じた一時ディスク容量が必要です。寸法変更は失敗にします。macOSは最小フレーム間隔を指定（既定30fps）します。すべて無音で、保護コンテンツは保証しません。Webはbrowser chromeとOS dialogを含まず、iOS/Androidは端末画面を含みます。macOSは他アプリも含む選択displayを記録し、windowを追従しません。

開始は最初の有効PNGまたはScreenCaptureKitの録画開始callbackを確認します。要求期限はrunnerのbuild/startを含み、backendの開始待ちは最大120秒です。iOS初回は`--timeout 120000`を指定してください。stop/closeは確定・保存を待ち、重複stopは同じ結果を返します。restartは旧動画を確定してから新規保存先へ開始します。自動再開・取得元fallback・UI再送は行いません。取得エラーとChromium切断は録画失敗です。変換期限は30秒です。要求timeout後も有界cleanupを継続します。

状態はidle/starting/recording/stopping/stopped/failed。成功dataはplatform・device・path・startedAt・elapsedMs・bytesを含み、elapsedMsは再生時間ではなく壁時計時間です。失敗statusはfailureとrecoveryPathを含みます。排他的に予約した出力先と同じ親のprivate stagingへ書き込み、確定失敗では復旧データを保持します。shutdownは最大60秒待ち、強制cleanupを追加5秒で制限します。SIGKILL/host停止後の自動復元は対象外。操作ref・VM接続世代を変更しません。

Chromiumは専用debug profileとloopback remote debuggingを使い、`/json/list`の正確なpage endpointを指定します。portは1〜65535、IDは大文字英数字です。remote host・認証情報・query・browser endpoint・旧`display:N@`形式・MOV出力を拒否します。機能不足はUNSUPPORTED_CAPABILITY、切断はCONNECTION_LOST、拒否・不正画像はIO_ERROR。サーバーの生メッセージを公開しません。WebにmacOSの画面収録許可は不要です。Android実機・iOS実機は今回の対象外です。

```sh
marionette-agent --timeout 120000 record start artifacts/ios.mp4 --platform ios --device "$SIMULATOR_UDID"
marionette-agent record stop
marionette-agent record start artifacts/android.mp4 --platform android --device "$CAPTURE_PAIRING"
marionette-agent record stop
marionette-agent record start artifacts/macos.mov --platform macos --device 1
marionette-agent record stop
marionette-agent record start artifacts/web.mp4 --platform web --device "$CHROME_PAGE_ENDPOINT"
marionette-agent record stop
```

## macOSのスクリーンショット

Flutter接続なしで画面番号を明示して撮影できます。他アプリを含む画面全体が保存されるため、共有前に画像を確認してください。呼出元terminal/host appの画面収録権限が必要です。表示中のpanel・menuも含みますが、保護されたUI・別Space・他画面は保証しません。ウィンドウの移動を追跡せず、権限不足・画面変更・timeout時はエラーになります。

```sh
marionette-agent device list --platform macos
marionette-agent screenshot --source macos --display 1 artifacts/native.png
```

macOSの静止画はXCTest/XCUIScreenで取得します。full Xcodeが必要で、初回ビルドを含め `--timeout 120000` を指定してください。3画面以上ではmain以外の撮影は未対応です。
