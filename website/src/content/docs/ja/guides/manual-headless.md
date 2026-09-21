---
title: 手動でheadlessアプリを起動する
description: iOSの専用device set、Android、macOS、Webのrunnerを自分で管理して接続・録画する手順。
---

通常の管理された起動は[headlessガイド](/marionette_agent/ja/guides/headless/)の`launch`を使います。本書はrunnerを自分で起動し、`connect`する場合だけの補足です。手動で起動したアプリはCLIのcloseでは終了しません。

<a id="preparation"></a>

## 共通の準備

macOSホストと選択した環境のSDK・端末を用意します。既存の実測はFlutter 3.47.2、Marionette 0.6.0の[example](https://github.com/r0227n/marionette_agent/blob/develop/example)に基づきます。各runnerは別ターミナルで`example/`から起動してください。以下で作ったMRA_HEADLESS_ROOTの値を、各ターミナルで同じpathに設定します。

```sh
umask 077
MRA_HEADLESS_ROOT=$(mktemp -d /tmp/mra-headless.XXXXXX)
chmod 700 "$MRA_HEADLESS_ROOT"
flutter pub get
```

認証URIとログはこのprivate directoryへ保存します。並行実行ではruntime・session・端末・出力先を分離し、同じcheckoutのbuildを競合させません。Flutter録画にはffmpeg（PNG/libx264/concat/setts）、一時PNG用の空き容量、停止時の変換時間が必要です。ホストをスリープさせないでください。

<a id="ios"></a>

## iOSの専用device set

`xcrun simctl list devicetypes`と`xcrun simctl list runtimes`からインストール済み識別子を選び、下記2変数を置き換えます。既定device setではSimulator.appが画面を開く場合があるため、専用setを使います。

```sh
MRA_DEVICE_TYPE='REPLACE_WITH_INSTALLED_DEVICE_TYPE'
MRA_IOS_RUNTIME='REPLACE_WITH_INSTALLED_IOS_RUNTIME'
flutter build ios --simulator --debug --no-pub
mkdir -m 700 "$MRA_HEADLESS_ROOT/ios-devices"
MRA_IOS_UDID=$(xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" create MRA-Headless \
  "$MRA_DEVICE_TYPE" "$MRA_IOS_RUNTIME")
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" boot "$MRA_IOS_UDID"
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" bootstatus "$MRA_IOS_UDID" -b
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" install "$MRA_IOS_UDID" build/ios/iphonesimulator/Runner.app
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" launch "$MRA_IOS_UDID" \
  com.example.example --enable-dart-profiling --enable-checked-mode --verify-entry-points
```

このbundle IDとapp pathはexample用です。自分のアプリでは置き換えてください。専用setは通常のflutter devicesには現れないため、simctlで操作します。Simulator.appでそのsetを開かないでください。bootstatusの終了だけでは成功を判断せず、実際のVM Service接続まで確認します。

```sh
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" spawn "$MRA_IOS_UDID" \
  log show --last 2m --style compact \
  --predicate 'process == "Runner" AND eventMessage CONTAINS "Dart VM service is listening"' \
  > "$MRA_HEADLESS_ROOT/ios-console.log" 2>&1
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

<a id="other-platforms"></a>

## Android、Web、macOS

Androidでは`emulator -list-avds`からAVDを選び、未使用の偶数portを使います。次のplaceholderは所有する環境に合わせて置き換えます。

```sh
emulator -avd YOUR_AVD -port 5586 -no-window -no-audio -no-snapshot-save -read-only
```

別ターミナルで`adb -s emulator-5586 shell getprop sys.boot_completed`が1になるまで待ってから起動します。

```sh
flutter run -d emulator-5586 --debug --no-pub \
  --vmservice-out-file="$MRA_HEADLESS_ROOT/android-uri"
```

WebはChromeのheadless runnerを使います。

```sh
flutter run -d chrome --debug --no-pub --web-run-headless \
  --vmservice-out-file="$MRA_HEADLESS_ROOT/web-uri"
```

macOSではnative環境変数とDart defineの両方が必要です。

```sh
MARIONETTE_HEADLESS=1 flutter run -d macos --debug --no-pub \
  --dart-define=MARIONETTE_HEADLESS=true \
  --vmservice-out-file="$MRA_HEADLESS_ROOT/macos-uri"
```

exampleのMainFlutterWindowはNSWindowを非表示にしてFlutterEngineを明示起動し、Dart側のenableHeadlessRendering()で描画を維持します。一般アプリにも同等の実装が必要です。ログイン済みGUI sessionとWindowServerは必要で、非表示のためforeground失敗の警告が出る場合があります。

<a id="verification"></a>

## 接続と確認

CLIをインストール済みとし、iOSの場合は次を実行します。他環境ではURI fileとsession名を置き換えてください。

```sh
mkdir -m 700 "$MRA_HEADLESS_ROOT/runtime-ios"
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_HEADLESS_ROOT/runtime-ios"
marionette-agent --session manual-ios connect "$(cat "$MRA_HEADLESS_ROOT/ios-uri")"
marionette-agent --session manual-ios snapshot
marionette-agent --session manual-ios record start "$MRA_HEADLESS_ROOT/ios.mp4" --platform flutter
marionette-agent --session manual-ios tap --key tap_button
marionette-agent --session manual-ios fill --key text_input 'headless demo'
marionette-agent --session manual-ios snapshot
marionette-agent --session manual-ios screenshot "$MRA_HEADLESS_ROOT/ios-after.png"
marionette-agent --session manual-ios --timeout 60000 record stop
marionette-agent --session manual-ios close
```

動画と画像でカウンタ・入力の変化を照合します。収録範囲は単一Flutter viewで、OS keyboard/dialogは含みません。fps・VFR・timeout・復旧は[録画の詳細](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/cli-reference.ja.md#recording)を参照してください。

自動smoke確認はCLI package内の[integration_test/record_smoke.dart](https://github.com/r0227n/marionette_agent/blob/develop/packages/marionette_agent/integration_test/record_smoke.dart)を使います。環境変数は`MARIONETTE_RECORD_PLATFORM=flutter`、`MARIONETTE_TEST_VM_URI_FILE`、毎回新しい`MARIONETTE_RECORD_EVIDENCE`を指定します。Androidの既存検証は`MARIONETTE_RECORD_FPS=2`を使っています。新たに実行していない検証結果を、この手順だけで実施済みとしないでください。

<a id="cleanup"></a>

## 所有した資源の後片付け

CLIをcloseした後に、各Flutter runnerへ`q`を送ります。専用iOSだけを以下で停止・削除します。

```sh
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" shutdown "$MRA_IOS_UDID"
xcrun simctl --set "$MRA_HEADLESS_ROOT/ios-devices" delete "$MRA_IOS_UDID"
```

Androidは今回のportの`adb -s emulator-5586 emu kill`で終了します。共有Simulatorやadb serverを止めず、不要なURI/logを削除し、確認済みの動画・結果を残します。testerのviewportと管理起動の制約は[headlessガイド](/marionette_agent/ja/guides/headless/)を参照してください。
