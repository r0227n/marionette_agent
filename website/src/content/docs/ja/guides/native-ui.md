---
title: ネイティブダイアログと写真ピッカー
description: XCUITestとUI Automatorのrunnerを使い、iOS SimulatorとAndroidのOS画面の要素取得・タップ・スワイプを行います。
---

権限ダイアログやOSの写真ピッカーがFlutter画面に重なった場合は`native`を使います。Flutter VM接続なしで明示した端末を操作できます。iOSはXCUITest / XCUIAutomation、AndroidはUI AutomatorのAPIを直接呼び出します。CLIはローカルのテストrunnerへ認証付き要求を送信します。ネイティブスクリーンショットは今回の機能の対象外です。

## runnerの準備

CLIと同じリポジトリrevisionのrunnerソースを使い、リポジトリルートでセットアップを実行します。iOS SimulatorにはXcodeとXcodeGen、AndroidにはSDK 36・JDK 17以上・起動済みエミュレータが必要です。Androidのビルドでは`JAVA_HOME`と`ANDROID_HOME`を設定します。Computer-use連携は不要です。

専用ディレクトリとランダムなtokenを作ります。このシェルを開いたままにしてください。runner設定と生のテストログはこのディレクトリに保存します。複数端末ではrunner・port・tokenを分け、設定ファイルに各端末のエントリをまとめます。

```sh
export MRA_NATIVE_DIR="$(mktemp -d /tmp/mra-native.XXXXXX)"
export MARIONETTE_AGENT_NATIVE_RUNNERS="$MRA_NATIVE_DIR/runners.json"
export MRA_NATIVE_TOKEN="$(openssl rand -hex 24)"
```

### iOS Simulator

`IOS_UDID`を起動済みSimulatorの正確なUUIDへ置き換え、観測するアプリのbundle IDを設定します。独立したUIテストbundleをビルドし、環境変数を設定して常駐テストを起動します。runnerは対象アプリを起動・前面化しません。テストrunnerの起動後にアプリを開いてください。システムalertがある場合、または対象アプリが前面にない場合はSpringBoard、それ以外では設定したアプリを観測します。

```sh
export MRA_NATIVE_PLATFORM=ios
export MRA_NATIVE_DEVICE=IOS_UDID
export MRA_NATIVE_PORT=18741
export MRA_APP_BUNDLE_ID=com.example.example
xcodegen generate --spec packages/marionette_agent_ios/native/project.yml
xcodebuild build-for-testing \
  -project packages/marionette_agent_ios/native/MarionetteNative.xcodeproj \
  -scheme MarionetteNative -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$MRA_NATIVE_DIR/ios-build" > "$MRA_NATIVE_DIR/build.log" 2>&1
python3 - <<'PYCODE'
import glob, os, plistlib
path = glob.glob(os.environ["MRA_NATIVE_DIR"] + "/ios-build/Build/Products/*.xctestrun")[0]
with open(path, "rb") as file:
    settings = plistlib.load(file)
target = settings["MarionetteNative"]
target["EnvironmentVariables"].update({
    "MRA_NATIVE_PORT": os.environ["MRA_NATIVE_PORT"],
    "MRA_NATIVE_TOKEN": os.environ["MRA_NATIVE_TOKEN"],
    "MRA_APP_BUNDLE_ID": os.environ["MRA_APP_BUNDLE_ID"],
})
target["TestTimeoutsEnabled"] = False
with open(path, "wb") as file:
    plistlib.dump(settings, file)
PYCODE
xcodebuild test-without-building \
  -xctestrun "$MRA_NATIVE_DIR"/ios-build/Build/Products/*.xctestrun \
  -destination "id=$MRA_NATIVE_DEVICE" -parallel-testing-enabled NO \
  > "$MRA_NATIVE_DIR/runner.log" 2>&1 &
MRA_NATIVE_PID=$!
```

### Androidエミュレータ

serialを対象エミュレータに置き換えます。2つのAPKはinstrumentation用hostとテストrunnerです。セットアップのadbはrunnerのインストール・起動とloopback portの転送だけに使用します。runner内の要素取得と入力は`UiDevice` / `UiObject2`を使い、nativeコマンドの実装はadb・shell input・XML dumpを実行しません。

```sh
export MRA_NATIVE_PLATFORM=android
export MRA_NATIVE_DEVICE=emulator-5554
export MRA_NATIVE_PORT=18742
packages/marionette_agent_android/native/gradlew \
  -p packages/marionette_agent_android/native assembleDebug assembleDebugAndroidTest
adb -s "$MRA_NATIVE_DEVICE" install -r \
  packages/marionette_agent_android/native/build/outputs/apk/debug/MarionetteNative-debug.apk
adb -s "$MRA_NATIVE_DEVICE" install -r \
  packages/marionette_agent_android/native/build/outputs/apk/androidTest/debug/MarionetteNative-debug-androidTest.apk
adb -s "$MRA_NATIVE_DEVICE" forward "tcp:$MRA_NATIVE_PORT" "tcp:$MRA_NATIVE_PORT"
adb -s "$MRA_NATIVE_DEVICE" shell am instrument -w \
  -e class dev.marionette.nativeui.NativeRunner \
  -e device "$MRA_NATIVE_DEVICE" -e port "$MRA_NATIVE_PORT" -e token "$MRA_NATIVE_TOKEN" \
  dev.marionette.nativeui.test/androidx.test.runner.AndroidJUnitRunner \
  > "$MRA_NATIVE_DIR/runner.log" 2>&1 &
MRA_NATIVE_PID=$!
```

### CLIを接続

対象OSのセットアップ後に実行します。JSON設定はplatformと正確な端末IDをloopback port・tokenに対応付けます。この環境で新しいCLI runtimeを起動してください。起動済みdaemonに環境変数の変更は伝わりません。別terminalやMCPの起動設定にも、exportした両方のpathを渡します。端末の設定がなければ`UNSUPPORTED_CAPABILITY`、runnerに接続できなければ`IO_ERROR`を返します。

```sh
python3 - <<'PYCODE'
import json, os
path = os.environ["MARIONETTE_AGENT_NATIVE_RUNNERS"]
if os.path.exists(path):
    with open(path) as file:
        config = json.load(file)
else:
    config = {}
config.setdefault(os.environ["MRA_NATIVE_PLATFORM"], {})[os.environ["MRA_NATIVE_DEVICE"]] = {
    "port": int(os.environ["MRA_NATIVE_PORT"]), "token": os.environ["MRA_NATIVE_TOKEN"]
}
with open(path, "w") as file:
    json.dump(config, file)
os.chmod(path, 0o600)
PYCODE
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_NATIVE_DIR/runtime"
marionette-agent --session app native snapshot \
  --platform "$MRA_NATIVE_PLATFORM" --device "$MRA_NATIVE_DEVICE"
```

テストrunnerの起動中は最初のsnapshotが接続エラーになる場合があります。準備後に観測をやり直してください。端末ごとに操作者は1つにします。別runtimeや外部ツールはdaemonの端末別queueとは独立しています。

## 権限ダイアログに応答

応答を選ぶ前に、実際のlabelとrefを確認します。文言は言語・OSにより異なります。`@n1`は取得したrefへ置き換え、入力後に再観測してください。最後のFlutterの`snapshot`には通常の`connect`が必要で、アプリへ戻ったことを確認できます。

```sh
marionette-agent --session app native snapshot --platform ios --device IOS_UDID
marionette-agent --session app native tap @n1 --platform ios --device IOS_UDID
marionette-agent --session app native snapshot --platform ios --device IOS_UDID
marionette-agent --session app snapshot
```

refの代わりに`--text`・`--identifier`・`--type`の完全一致を指定できます。0件または複数件の一致では入力せず失敗します。nativeの`@n` refとFlutterの`@e` refは相互利用できません。

## 写真の選択とスワイプ

アプリからピッカーを開き、`native snapshot`で観測して、現在の写真や確定ボタンのrefをtapします。swipeの座標は現在の端末画面や観測したboundsから決め、結果を再観測して新しいrefを使ってください。次の座標とrefは例であり、全端末に共通のピッカー位置ではありません。

```sh
marionette-agent --session app native swipe --platform android --device emulator-5554 \
  --start-x 360 --start-y 1000 --end-x 360 --end-y 400
marionette-agent --session app native snapshot --platform android --device emulator-5554
marionette-agent --session app native tap @n8 --platform android --device emulator-5554
```

座標指定の`tap --x X --y Y`も使えます。iOSの座標はscreen pointで、dragにはOS既定の速度を使います。Androidは物理pixelを整数へ丸め、swipeは60 step（約300ms）で実行します。画面の向きとscaleに注意してください。アクセシビリティで取得できないコントロールがあり、空またはrootのみのsnapshotでは制限を返します。座標への自動fallbackは行いません。対象がなければSimulator・エミュレータの画面を直接確認してください。画面撮影は別機能です。

## ref・policy・エラー

native snapshotは`source: native`、platform、device、座標単位、generation、bounds付きの正規化要素を返します。`--json`・`--content-boundaries`・`--max-output`・期限・通常のエラー包絡を適用します。refのtapではboundsを含む全要素情報を再観測してから1回だけ入力します。移動・消失・重複した対象では失敗します。観測と入力はOS上の不可分な操作ではありません。

native tap/swipeは同じ端末のnative refをsession横断で失効させ、daemon内の全Flutter refも失効させます。Flutterの変更操作はそのsessionのnative refを失効させます。読み取りはFlutter refを保持します。policyではtap/swipeを`native`として制御します。送信後の失敗・timeoutで`outcome: unknown`となった場合は、実画面を観測してから次を判断し、自動再送しないでください。

MCPの`--tools core,native`は`marionette_agent_native_snapshot`・`marionette_agent_native_tap`・`marionette_agent_native_swipe`を公開します。毎回platformとdeviceが必要です。nativeはbatch・workflow v1には含めません。

## runnerを停止

```sh
marionette-agent --session app close
kill "$MRA_NATIVE_PID"
wait "$MRA_NATIVE_PID" || true
```

Androidではさらに`adb -s "$MRA_NATIVE_DEVICE" shell am force-stop dev.marionette.nativeui`でrunnerを停止し、`adb -s "$MRA_NATIVE_DEVICE" forward --remove "tcp:$MRA_NATIVE_PORT"`で自分の転送を解除します。アプリの停止と所有するエミュレータ・Simulatorの解放は別途行います。CLI sessionのcloseは外部起動したrunnerや端末を終了しません。
