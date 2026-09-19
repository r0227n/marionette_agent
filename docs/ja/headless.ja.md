# ヘッドレス実行と録画

## 対応範囲

Flutter testerとiOS・Android・macOS・Webの各実行環境を明示的に選び、ウィンドウを表示せずにMarionette対応Flutterアプリを操作・録画します。

| 対象 | 実行環境 | 非表示にする方法 | 録画 |
| --- | --- | --- | --- |
| tester | テスト用Flutterエンジン | flutter-tester | Flutter描画 → MP4 |
| iOS | iOS Simulator | 専用device setでboot・launch | Flutter描画 → MP4 |
| Android | Android Emulator | `-no-window` | Flutter描画 → MP4 |
| macOS | ネイティブFlutterEngine | 非表示NSWindow + debug描画維持 | Flutter描画 → MP4 |
| Web | Chrome | `--web-run-headless` | Flutter描画 → MP4 |

すべて接続済みsessionで`record start <new.mp4> --platform flutter`を使います。録画形式は無音H.264、対象は単一のFlutter viewです。OSキーボード、OSダイアログ、ブラウザーUIやplatform viewの録画は保証しません。macOSの画面収録許可は不要ですが、Marionette debug bindingが必要です。OS全体を録画する既存の`--platform ios/android/macos/web`とは前提が異なります。[CLIリファレンス](cli-reference.ja.md#flutterアプリの録画ヘッドレス対応)に各コマンドの契約があります。

## 必要なもの

- macOSホスト。選んだ環境に応じてXcodeとiOS Simulator、Android SDKとAVD、Google Chrome。
- Flutter 3.47.2、Marionette 0.6.0と[example](../../example/)のdebugアプリ。
- PATH上のffmpeg。PNG decoder、libx264 encoder、concat demuxer、setts bitstream filterが必要です。検証にffprobeも使います。
- ログイン済みGUIセッション。macOSはウィンドウを非表示にできますが、WindowServerがないホストでの動作は検証していません。
- 動画と一時PNGを保存するディスク容量。録画時間と描画量に応じて増えます。
- 録画中にホストをスリープさせないこと。プロセスが中断すると取得・接続確認が期限切れになり、再接続が必要になる場合があります。

## 実行環境を選んで起動する

`launch <project> --platform tester|ios|android|macos|web`は、選んだ環境でdebugアプリを起動し、同じsessionへ接続します。testerはFlutter共通UIの反復確認、各OS／Webは対象環境での確認に使います。環境を自動切替したり、失敗した操作を別環境へ再送したりしません。

Flutter SDK・各OSのSDK・Chrome・ffmpegと、projectの依存を事前に用意してください。`launch`は`--no-pub`でビルドします。初回ビルドと端末bootには共通`--timeout`を十分長く指定します。以下はリポジトリルートでの例です。

```sh
marionette-agent --session fast --timeout 600000 launch ./example --platform tester
marionette-agent --session fast record start ./tester.mp4 --platform flutter
marionette-agent --session fast tap --key tap_button
marionette-agent --session fast fill --key text_input 'hybrid check'
marionette-agent --session fast screenshot ./tester.png
marionette-agent --session fast --timeout 60000 close
```

`launch`の成功は、起動プロセスの存在だけでなくVM Service接続とMarionetteの最初の観測まで確認した状態です。結果は接続情報に`application`（platform、state、runnerのpid、必要時device）を追加します。URIの認証部分は秘匿されます。`session show`で接続と所有アプリを確認できます。

各環境へ切り替える場合は、前のsessionをcloseしてから次を起動し、同じtap/fill/record/workflowコマンドを使います。

```sh
marionette-agent --session ios --timeout 600000 launch ./example --platform ios \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-Air \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-2
marionette-agent --session ios --timeout 60000 close

marionette-agent --session android --timeout 600000 launch ./example --platform android \
  --avd Pixel_9_Pro --port 5586
marionette-agent --session android --timeout 60000 close

marionette-agent --session macos --timeout 600000 launch ./example --platform macos
marionette-agent --session macos --timeout 60000 close

marionette-agent --session web --timeout 600000 launch ./example --platform web
marionette-agent --session web --timeout 60000 close
```

| オプション | 意味 |
| --- | --- |
| `--platform` | 必須。tester／ios／android／macos／webを明示 |
| `--flutter` | Flutter実行ファイル。省略時daemonのPATH上のflutter。SDKを固定する場合は絶対pathを指定 |
| `--target` | entrypoint。project相対または絶対path。既定`lib/main.dart` |
| `--device-type`、`--runtime` | iOSのみ必須。インストール済みSimulatorの識別子 |
| `--avd`、`--port` | Androidのみ必須。既存AVD名と未使用の偶数port（5554〜5682） |

他環境のオプション、未知field、無効値はINVALID_ARGUMENTです。起動済みsessionへのlaunchや利用中project／Android portはSESSION_CONFLICTになります。同一projectのビルド出力を共有しないよう、同時に1つの管理対象アプリだけを許可します。別projectを使う場合もruntime・session・端末・出力先を分離してください。

### 起動と終了の所有権

- `launch`はutilがprivate一時領域を作り、tester／Flutter runner／headless Chrome、専用iOS device set、読み取り専用Android Emulatorを所有します。共有のSimulatorやadb serverは停止しません。
- **launchしたsessionのcloseは、録画を確定してから所有アプリ・端末を終了します。** close --all、daemonの正常終了も同じ所有権を回収します。
- 手動起動したアプリへの`connect`は接続だけを所有します。この場合のcloseはアプリを終了しません。
- 起動失敗・期限切れ・接続準備失敗では、所有するプロセス・端末と一時URIを回収します。期限切れの応答後も有界な回収が続く場合があり、session状態を確認してから再実行してください。
- 実行中のアプリ終了で接続・refを失効します。自動再起動や操作の自動再送はしません。OS内の処理、SIGKILL、ホスト停止後の回収は保証しません。
- Androidは既存AVDを`-read-only -no-snapshot -no-window`で起動します。AVD自体を作成・削除せず、保存済みデータへ変更を保存しません。十分な空き容量が必要です。
- macOSはアプリ側にも非表示NSWindowとdebug描画維持の対応が必要です。exampleには実装済みで、utilが環境変数とDart defineを渡します。一般アプリを自動的に非表示対応へ改変する機能ではありません。

### testerの範囲

testerはFlutterのDartコードをテスト用エンジンで実行します。iOS／Androidのネイティブ実装やブラウザーを再現するものではありません。今回のFlutter 3.47.2ではdebug限定で、論理800×600・DPR 3の固定viewportです。OSプラグイン、権限、キーボード、Web固有コードや実機性能は各実行環境で確認します。見た目のplatform overrideはOSを変更しません。

録画は他の環境と同じ`--platform flutter`を使います。画面外の要素はscrollで表示させ、swipe距離はviewportに合わせます。過去の300px swipeでPage 1に残った例と、500pxでの確認は[調査記録](../headless-feasibility-issue-20.md)に記載しています。

800×600で確認した[JSON workflow](../../packages/marionette_agent/examples/workflows/headless-controls.json)と[YAML workflow](../../packages/marionette_agent/examples/workflows/headless-controls.yaml)を同梱しています。Controlsへ戻った後、200px上へscrollしてページ表示を可視範囲に置き、500px左へswipeします。最終snapshotの`page_result`が`Current page: 2`であることを確認し、同じsnapshotの`text_input`のrefを次のCLIから利用できます。この距離はexample向けで、他アプリの既定値ではありません。

```sh
marionette-agent --session fast workflow run packages/marionette_agent/examples/workflows/headless-controls.yaml
marionette-agent --session fast snapshot
```

## 手動で起動・接続する場合

macOSホスト、Flutter 3.47.2、Marionette 0.6.0、ffmpeg（PNG/libx264）で検証。OS／SDKと端末は事前に用意します。各runnerは別ターミナルで`example/`から実行し、検証に所有する端末・専用の出力先を使います。URIやFlutterログは認証情報を含むのでprivateディレクトリに保存してください。

```sh
MRA_HEADLESS_ROOT=$(mktemp -d /tmp/mra-headless.XXXXXX)
chmod 700 "$MRA_HEADLESS_ROOT"
flutter pub get
```

- **iOS**: 専用device setでboot・install・launchを行います。既定のdevice setでは起動中のSimulator.appがウィンドウを開く場合があるため分離します。手順は下記を参照してください。
- **Android**: `emulator -list-avds`でAVDを選び、`emulator -avd <AVD> -port <未使用の偶数port> -no-window -no-audio -no-snapshot-save -read-only`を起動します。`adb -s emulator-<port> shell getprop sys.boot_completed`が1になった後、`flutter run -d emulator-<port> --debug --no-pub --vmservice-out-file="$MRA_HEADLESS_ROOT/android-uri"`を実行します。
- **Web**: `flutter run -d chrome --debug --no-pub --web-run-headless --vmservice-out-file="$MRA_HEADLESS_ROOT/web-uri"`を実行します。Chromeのheadlessプロセス上で実行されます。
- **macOS**: `MARIONETTE_HEADLESS=1 flutter run -d macos --debug --no-pub --dart-define=MARIONETTE_HEADLESS=true --vmservice-out-file="$MRA_HEADLESS_ROOT/macos-uri"`を実行します。MainFlutterWindowがNSWindowの表示を抑え、FlutterEngineを明示起動します。Dart側の`enableHeadlessRendering()`が非表示時も描画を維持します。両方の指定が必要です。非表示のためforegroundに失敗した旨のFlutter警告が出る場合があります。ログイン済みmacOSのWindowServerは必要です。

### iOS: GUIから分離する専用device set

`example/`でdebugのSimulator向けアプリをビルドし、`xcrun simctl list devicetypes`と`xcrun simctl list runtimes`に存在するdevice type／runtimeを選びます。以下のiPhone Air／iOS 26.2は検証時の値です。device setは毎回新しいprivate directoryを使います。

```sh
flutter build ios --simulator --debug --no-pub
mkdir -m 700 "$MRA_HEADLESS_ROOT/ios-devices"
MRA_IOS_UDID=$(xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" create MRA-Headless \
  com.apple.CoreSimulator.SimDeviceType.iPhone-Air \
  com.apple.CoreSimulator.SimRuntime.iOS-26-2)
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" boot "$MRA_IOS_UDID"
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" bootstatus "$MRA_IOS_UDID" -b
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" install "$MRA_IOS_UDID" build/ios/iphonesimulator/Runner.app
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" launch "$MRA_IOS_UDID" \
  com.example.example --enable-dart-profiling --enable-checked-mode --verify-entry-points
```

起動後のVM Service URIはSimulator内のアプリログに出ます。専用デバイスのログをprivateファイルへ取り出して抽出します。URIは画面や共有ログへ転記しません。

```sh
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" spawn "$MRA_IOS_UDID" \
  log show --last 2m --style compact \
  --predicate 'process == "Runner" AND eventMessage CONTAINS "Dart VM service is listening"' \
  > "$MRA_HEADLESS_ROOT/ios-console.log" 2>&1
```

```sh
python3 - "$MRA_HEADLESS_ROOT" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
match = re.search(r'Dart VM service is listening on (http://[^\s]+)',
                  (root / 'ios-console.log').read_text())
if match is None:
    raise SystemExit('VM Service is not ready; check the private app log')
(root / 'ios-uri').write_text(match.group(1))
(root / 'ios-uri').chmod(0o600)
PY
```

Flutter CLIのdevice一覧は通常のdevice setを使うため、この専用デバイスへの起動は上記のsimctl経路で行います。Simulator.appで専用セットを開かないでください。初回bootのデータ移行には時間がかかります。bootstatusの終了コードだけで成功を判断せず、実アプリのVM Serviceへ接続できることを確認してください。今回の初回bootではData Migration Failedの通知後もOSとアプリが起動し、録画まで成功しました。

### 共通: 接続・操作・録画

接続後は4環境とも`record --platform flutter`を使います。これはアプリのFlutter描画だけの録画です。以下はrepoルートからのiOS例で、他の環境はURIファイルとsession名を置き換えます。runtimeと動画出力先を環境ごとに分けてください。

```sh
mkdir -m 700 "$MRA_HEADLESS_ROOT/runtime-ios"
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_HEADLESS_ROOT/runtime-ios"
CLI=packages/marionette_agent/bin/marionette_agent.dart
dart "$CLI" --session headless-ios connect "$(cat "$MRA_HEADLESS_ROOT/ios-uri")"
dart "$CLI" --session headless-ios record start "$MRA_HEADLESS_ROOT/ios.mp4" --platform flutter
dart "$CLI" --session headless-ios tap --key tap_button
dart "$CLI" --session headless-ios fill --key text_input 'headless demo'
dart "$CLI" --session headless-ios screenshot "$MRA_HEADLESS_ROOT/ios-after.png"
dart "$CLI" --session headless-ios --timeout 60000 record stop
dart "$CLI" --session headless-ios close
```

録画を再生し、カウンタと入力文字数の変化を照合します。毎秒の実取得枚数は描画・転送時間に依存します。OSキーボードやダイアログは収録範囲外です。CLIをcloseした後、各Flutter runnerへ`q`を送り、専用iOSだけを`xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" shutdown "$MRA_IOS_UDID"`、Androidだけを`adb -s emulator-<port> emu kill`で終了します。共有のSimulatorやadb serverは終了しません。iOSの停止後は`xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" delete "$MRA_IOS_UDID"`で今回作成したデバイスだけを削除します。URIファイルを削除し、動画・検証結果を残します。

自動確認はCLIパッケージ内で次を実行します（録画開始、tap/fill、重複stop、既存出力保護、closeによる確定）。出力ディレクトリは毎回新しくしてください。

```sh
MARIONETTE_RECORD_PLATFORM=flutter \
MARIONETTE_TEST_VM_URI_FILE="$MRA_HEADLESS_ROOT/ios-uri" \
MARIONETTE_RECORD_EVIDENCE="$MRA_HEADLESS_ROOT/ios-evidence" \
dart run integration_test/record_smoke.dart
```

Androidの確認では上記に`MARIONETTE_RECORD_FPS=2`を追加します。検証用AVDにはアプリのインストールに十分な空き容量を用意してください。ホストのスリープ中やPNG取得が5秒を超える環境での録画継続は保証しません。

## 録画方式と制限

`--fps`は1〜60、既定10です。今回のAndroidの確認は`--fps 2`、他の4環境は既定値で実施しました。1回のPNG取得・保存が完了してから次の取得までの待機間隔を指定するため、実際の取得頻度は指定値より低くなります。録画には実際の取得時刻を使い、VFR（可変フレームレート）で保存します。高速アニメーションを全フレーム記録する用途には向きません。

startは先頭PNGを確認して返ります。stopやcloseは取得を終えてMP4を確定します。変換は最大30秒で、コマンドの要求期限を超えても有界な保存処理は続きます。TIMEOUTなら`record status`で最終結果を確認し、UI操作を自動再送しないでください。`elapsedMs`には確定待ちが含まれ、動画の再生時間とは異なります。

録画専用の接続を使うため、停止しても操作用sessionのrefやキー状態を変更しません。録画用接続の断、取得失敗、寸法変更、動画変換失敗は失敗として返し、白画像で成功に置き換えません。failed時の`recoveryPath`にはPNGや途中動画が残る場合があります。hot restart中の録画継続は保証しません。

## よくある確認事項

| 状況 | 確認すること |
| --- | --- |
| NOT_CONNECTED | 同じsessionにVM Serviceで先にconnectしたか |
| `--device`のINVALID_ARGUMENT | `--platform flutter`ではdeviceを省略する |
| ffmpegが見つからない | daemonを起動する環境のPATHとPNG/libx264/setts対応 |
| macOSで起動しても画面変化がない | native環境変数とDart defineの両方を指定したか。一般アプリにはexample同等のnative window処理も必要 |
| iOSの表示ウィンドウが開く | 上記の専用device setを使う。既定セットはSimulator.appが表示する場合がある |
| 録画が低fps | PNG取得にかかる時間が上乗せされる。高速なUI変化を見落としていないか、実動画で確認する |
| 既存動画へのstartが失敗する | 上書きしない契約。新しい出力先を使う |

## 検証結果と設計

testerを含む5環境の実測値・動画・非表示の確認・全体テスト・後片付けは[Issue #20の検証記録](../../packages/marionette_agent/docs/verification/issue-20.md)にまとめています。[SPEC](../SPEC.md#flutterアプリのヘッドレス録画issue-20)と[ARCHITECTURE](../ARCHITECTURE.md#非表示アプリの描画録画issue-20)を実装契約として参照してください。初期のFlutter tester案の調査は[過去の調査記録](../headless-feasibility-issue-20.md)です。
