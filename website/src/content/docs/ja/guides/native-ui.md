---
title: ネイティブダイアログと写真ピッカー
description: XCUITestとUI Automatorのrunnerを使い、iOS SimulatorとAndroidのOS画面の要素取得・タップ・スワイプを行います。
---

sessionにnative端末を紐付けると、FlutterのUI・権限ダイアログ・OSの写真ピッカーを同じ`snapshot`・`tap`・`swipe`で扱えます。Flutter VM接続なしでも端末を操作でき、VMを接続すると同じsessionでFlutterも観測します。iOSはXCUITest / XCUIAutomation、AndroidはUI Automatorを認証付きローカルrunner経由で利用します。画面撮影は別機能です。

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
marionette-agent --session app session bind \
  --platform "$MRA_NATIVE_PLATFORM" --device "$MRA_NATIVE_DEVICE"
marionette-agent --session app snapshot
```

テストrunnerの起動中は最初のsnapshotが接続エラーになる場合があります。準備後に観測をやり直してください。端末ごとに操作者は1つにします。別runtimeや外部ツールはdaemonの端末別queueとは独立しています。

## 権限ダイアログの観測と応答

`snapshot`は接続済みならFlutter、端末登録済みならnative、両方あれば両方を観測します。`--source flutter|native|all`で明示選択できます。snapshotのたびに両取得元の古いrefを置換します。混在結果は各行に取得元と座標系を持ち、重複したUIを統合せず、native行を先に表示します。要求した取得元の失敗時は観測全体が失敗しrefを失効します。nativeが空/rootのみの場合は制限を返します。

応答を選ぶ前に実際のラベルとrefを読みます。言語・OSでラベルが変わるため、以下のrefは現在のsnapshotの値に置き換えてください。同じコマンドが`@e`をFlutter、`@n`をnativeへ送ります。sourceでrefの取得元を上書きできません。`connect`は`session bind`の前後で利用できます。端末紐付けは利用者による宣言であり、両接続が同じアプリを対象とすることの検証ではありません。

```sh
marionette-agent --session app snapshot
marionette-agent --session app tap @e1
marionette-agent --session app snapshot
marionette-agent --session app tap @n1
marionette-agent --session app snapshot
```

nativeの完全一致`--text`・`--identifier`・`--type`には`--source native`を付けます。指定なしのselectorと座標は従来のFlutterの意味です。0件・複数件の一致では入力しません。既知のnative alertではFlutter入力を拒否し、混在snapshotのFlutter refを抑止します。それ以外の遮蔽は不明なため、ピッカーがFlutterを覆う場合は端末を確認してnative側を選びます。

## 写真の選択とswipe

`tap`でピッカーを開き、`snapshot`で観測し、現在の写真・確定ボタンのrefをtapします。同じ`swipe`が両取得元のrefと指の方向を受け付けます。nativeの距離はその画面座標系の単位です。以下のref・座標は例なので、現在の端末のboundsを先に確認してください。

```sh
marionette-agent --session app swipe @e2 left --distance 200
marionette-agent --session app snapshot
marionette-agent --session app swipe @n8 up --distance 200
marionette-agent --session app snapshot
marionette-agent --session app swipe --source native \
  --start-x 360 --start-y 1000 --end-x 360 --end-y 400
marionette-agent --session app snapshot
marionette-agent --session app tap --source native --text Allow
```

native座標tapは`tap --source native --x X --y Y`です。iOSはscreen pointsと標準drag速度、Androidは整数へ丸めた画面pixelと60 swipe steps（約300ms）を使います。向き・倍率を考慮してください。座標への代替や取得元を切り替えた再送は行いません。native snapshotはcompactと完全一致text/identifier/type filterに対応し、interactive・depth・key filterには`--source flutter`を使います。nativeのfill等の未対応操作は入力前に拒否します。

## ref・policy・エラー

`--json`・`--content-boundaries`・`--max-output`・期限・通常のエラーを適用します。未公開refは使えません。ref操作では取得元を再観測してから1回入力し、移動・消失・重複した対象では失敗します。観測と入力はOS上の不可分な操作ではありません。

native入力は同じ端末のnative refをsession横断で失効させ、daemon内の全Flutter refも失効させます。Flutter入力は自sessionと同じ端末に紐付いた他sessionの両観測を失効させます。再bindは両観測と承認待ちを失効します。snapshot以外の読み取りはrefを保持します。nativeのtap/swipeはpolicy actionの`native`を維持します。`outcome: unknown`では実画面を観測してから次を判断し、自動再送しません。

MCPの`core` profileは`marionette_agent_session_bind`・`marionette_agent_snapshot`・`marionette_agent_tap`・`marionette_agent_swipe`を公開します。旧nativeコマンド・native MCP tools・native profileは廃止しました。batchのtap/swipeとsnapshotは端末登録済みsessionで同じserviceへ送ります。workflowのsnapshotも両取得元を観測できますが、workflow v1の変更操作selectorはFlutterのみです。

## runnerを停止

```sh
marionette-agent --session app close
kill "$MRA_NATIVE_PID"
wait "$MRA_NATIVE_PID" || true
```

Androidではさらに`adb -s "$MRA_NATIVE_DEVICE" shell am force-stop dev.marionette.nativeui`でrunnerを停止し、`adb -s "$MRA_NATIVE_DEVICE" forward --remove "tcp:$MRA_NATIVE_PORT"`で自分の転送を解除します。アプリの停止と所有するエミュレータ・Simulatorの解放は別途行います。CLI sessionのcloseは外部起動したrunnerや端末を終了しません。
