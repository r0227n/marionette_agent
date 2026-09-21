---
title: headlessで操作・録画する
description: tester・iOS・Android・macOS・Webの選び方、非表示起動、Flutter描画の録画、終了と復旧の手順。
---

headlessでは、アプリのウィンドウを表示せずにFlutter UIを観測・操作します。`launch`は選んだ環境でdebugアプリをビルド・起動し、VM Serviceへの接続と最初の観測まで行います。起動後は通常と同じsnapshot・tap・fill・workflowを使い、画像や動画で結果を確認できます。

ホストはmacOSです。GUIを表示しないことと、GUI環境やOSのSDKが不要なことは同じではありません。操作対象アプリには[Marionetteの初期化](/marionette_agent/ja/getting-started/app-integration/)が必要です。

## 確認したい内容から環境を選ぶ

| Platform  | 非表示にする方法            | 向いている確認と前提                                          |
| --------- | --------------------------- | ------------------------------------------------------------- |
| `tester`  | Flutterのテスト用エンジン   | 共通Flutter UIの反復確認。検証済みSDKはFlutter 3.47.2         |
| `ios`     | 専用Simulator device set    | iOS上の挙動。Xcode、インストール済みdevice type/runtimeが必要 |
| `android` | 既存AVDを`-no-window`で起動 | Android上の挙動。Android SDK、AVD、未使用の偶数portが必要     |
| `macos`   | 非表示NSWindowと描画維持    | macOSアプリ。アプリ側の対応とログイン済みGUI sessionが必要    |
| `web`     | headless Chrome             | Flutter Webの挙動。Google Chromeが必要                        |

testerはiOSやAndroidのネイティブ実装を再現しません。OS plugin、権限、keyboard、Web固有コード、実機性能は対象環境で確認してください。見た目のplatform overrideを変えても実行OSは変わりません。失敗したときの環境自動切替や、UI操作の自動再送は行いません。

## 起動前に依存関係を準備する

CLIの[インストール](/marionette_agent/ja/getting-started/installation/)を済ませ、exampleの依存を取得します。以下はリポジトリルートから実行します。

```sh
flutter pub get
```

`launch`は`--no-pub`でビルドします。初回buildと端末bootも含めてtimeoutを長く指定してください。録画にはPATH上のffmpegと、一時PNG・動画用の空き容量も必要です。

## testerで操作を確認する

```sh
marionette-agent --session fast --timeout 600000 launch ./example --platform tester
marionette-agent --session fast snapshot
marionette-agent --session fast tap --key tap_button
marionette-agent --session fast get text --key tap_result
marionette-agent --session fast fill --key text_input 'headless check'
marionette-agent --session fast snapshot
marionette-agent --session fast screenshot
```

`tap_result`のカウントが増え、入力欄の値が変わったことを観測と保存画像で照合します。成功応答だけでは意図した画面変化を保証しません。refを使う場合は操作後にsnapshotを取り直します。

検証済みSDKのtesterはdebug専用で、viewportは論理800×600、DPR 3です。画面外要素を先にscrollして表示し、swipe距離をviewportに合わせてください。example用の次のworkflowでは、Controls画面を表示し、200px上へscrollした後に500px左へswipeします。

```sh
marionette-agent --session fast workflow run \
  samples/workflows/headless-controls.yaml --json
```

`finalSnapshot`の`page_result`が`Current page: 2`であることを確認します。これらの距離はexample向けで、他アプリの既定値ではありません。[workflowガイド](/marionette_agent/ja/guides/workflows/)で失敗時の進捗と再観測も確認してください。

## Flutter描画を動画へ保存する

上で起動したsessionを使います。出力先は毎回新しいpathを選びます。

```sh
mkdir -p artifacts
marionette-agent --session fast record start artifacts/headless.mp4 --platform flutter --fps 10
marionette-agent --session fast tap --key tap_button
marionette-agent --session fast snapshot
marionette-agent --session fast record status --json
marionette-agent --session fast --timeout 60000 record stop --json
marionette-agent --session fast --timeout 60000 close
```

動画は単一Flutter viewの無音H.264 MP4です。`--device`は指定しません。OS keyboard/dialog、ブラウザーのUI、platform viewの収録は保証せず、macOSの画面収録許可は不要です。OS全体の画面が必要なら[端末録画](/marionette_agent/ja/guides/capture/)の方式を選びます。

fpsは1〜60、既定10です。各PNG取得後に指定間隔を待ち、実際の取得時刻に基づくVFR動画を作るため、一定fpsや高速アニメーションの全frameは保証しません。stopは動画変換まで待ちます。TIMEOUTなら`record status`で最終結果を確認し、失敗時は`failure/recoveryPath`を調べます。画像寸法の変化・接続断・変換失敗を白い成功動画へ置き換えることはありません。

## iOSとAndroidで確認する

環境を切り替える前に前のsessionをcloseしてください。同じprojectの管理対象アプリは同時に1つだけです。次のコマンドで利用可能な識別子・AVDを調べます。

```sh
xcrun simctl list devicetypes
xcrun simctl list runtimes
emulator -list-avds
```

以下の識別子・AVD名は例です。インストール済みのものへ置き換えてください。

```sh
marionette-agent --session ios --timeout 600000 launch ./example --platform ios \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-Air \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2
marionette-agent --session ios snapshot
marionette-agent --session ios --timeout 60000 close

marionette-agent --session android --timeout 600000 launch ./example --platform android \
  --avd Pixel_9_Pro --port 5586
marionette-agent --session android snapshot
marionette-agent --session android --timeout 60000 close
```

iOSは既定setから分離した専用device setを使います。Androidのportは5554〜5682の未使用の偶数です。既存AVDをread-only・no-snapshot・no-windowで起動し、保存済み状態へ変更を書き戻しません。AVD自体は作成・削除しません。録画は両方とも`--platform flutter`を使えます。

## macOSとWebで確認する

```sh
marionette-agent --session macos --timeout 600000 launch ./example --platform macos
marionette-agent --session macos snapshot
marionette-agent --session macos --timeout 60000 close

marionette-agent --session web --timeout 600000 launch ./example --platform web
marionette-agent --session web snapshot
marionette-agent --session web --timeout 60000 close
```

macOSではexampleのように、native側でNSWindowの表示を抑えてFlutterEngineを起動し、Dart側の`enableHeadlessRendering()`で非表示時の描画を維持する対応が必要です。launchは環境変数`MARIONETTE_HEADLESS=1`とDart defineを渡しますが、任意のアプリを自動で改変しません。WindowServerのないホストでの動作を前提にしないでください。

WebはChromeをheadless起動します。非表示のFlutter Web録画にも`record --platform flutter`を使います。`record --platform web`はmacOSの可視displayを録画する別方式です。

## 起動オプションと所有権

`--flutter`でFlutter実行ファイルを固定でき、`--target`でentrypointを指定できます（既定`lib/main.dart`）。iOSのdevice-type/runtime、Androidのavd/portは必須で、他環境のoptionを混ぜると引数エラーです。

成功時のdataと`session show`には`application:{platform,state,pid,device?}`が含まれます。stateはrunning/exited、pidは所有runnerです。launch成功はprocessが存在するだけでなく、VM Service接続と最初のMarionette観測を確認した状態です。

closeは録画を確定してから、そのsessionが所有するアプリ・端末を終了します。共有Simulatorやadb server全体は停止しません。起動失敗や期限切れでも所有資源を回収しますが、応答後も有界な回収が続く場合があります。アプリ終了で接続・refは失効し、自動再起動しません。SIGKILLやhost停止後の自動復元はありません。

自分でrunnerを起動しconnectした場合は、close後もアプリが残ります。その方法が必要なら[手動headlessセットアップ](/marionette_agent/ja/guides/manual-headless/)へ進んでください。

## うまく動かないとき

| 状況                               | 確認すること                                                                           |
| ---------------------------------- | -------------------------------------------------------------------------------------- |
| SESSION_CONFLICT                   | 同じsession/project/Android portを別の起動が使用していないか。前のsessionをcloseしたか |
| 起動時TIMEOUT                      | 初回build・bootに十分な期限か。session showで回収後の状態を確認する                    |
| UNSUPPORTED_CAPABILITY             | SDK実行ファイル・Chrome・ffmpegと、必要なアプリ側capabilityがあるか                    |
| macOSの画像が変わらない            | native window処理とDart描画維持の両方を実装したか                                      |
| iOSのwindowが表示される            | 専用device setを使っているか。手動でSimulator.appに開いていないか                      |
| 録画が低fps・停止する              | PNG取得時間、空き容量、host sleep、寸法変更、接続断を確認する                          |
| screenshotやrecordの保存に失敗する | 親directoryが存在し、出力pathが新しいか                                                |
