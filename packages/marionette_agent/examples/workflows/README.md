# 全コマンドの動作確認

[all-actions.yaml](all-actions.yaml) はworkflow v1の全6 actionを使う16ステップのシナリオです。Aboutへの移動・復帰、tap、fill、PageViewのswipe、scroll、wait、snapshotを実行します。対象はリポジトリの [exampleアプリ](../../../../example/README.md) です。

workflow v1には接続、get、画像、ログ、録画などのactionがありません。それらは [all_commands_smoke.dart](../../integration_test/all_commands_smoke.dart) が製品CLIの別プロセスとして実行します。YAMLの検証と実行も同じスクリプトに含みます。iOSとAndroidで同じシナリオを使い、端末IDとrecordのplatformだけを切り替えます。

## 準備

macOS、リポジトリで指定するFlutter/Dart、iOS Simulator用のXcode、Android用のSDK・adb・起動可能なAVDが必要です。CLIの `doctor` はmacOSホストとiOS Simulatorを診断するため、Androidの検証でもXcodeが必要です。Androidの起動状態と実際の操作結果は本シナリオで別途確認します。

リポジトリルートで依存を取得します。

```sh
(cd packages/marionette_agent && dart pub get)
(cd example && flutter pub get)
flutter devices
xcrun simctl list devices available
adb devices -l
```

未使用のiOS SimulatorとAndroid Emulatorを選び、端末を起動してください。既存の別タスクの端末・sessionは共有しないでください。同一端末での実行は、アプリ起動から録画・CLI終了・アプリ終了まで直列にします。

次はリポジトリルートからの例です。`MRA_DEVICE`は実在するIDへ置き換えます。iOS、Androidそれぞれでこの手順を実行してください。

```sh
umask 077
MRA_ROOT="$PWD"
MRA_RUN=$(mktemp -d /tmp/mra-all.XXXXXX)
mkdir -m 700 "$MRA_RUN/private" "$MRA_RUN/evidence"
MRA_PLATFORM=ios
MRA_DEVICE='<iOS Simulator UDID>'
# Androidの場合:
# MRA_PLATFORM=android
# MRA_DEVICE=emulator-5580

cd "$MRA_ROOT/example"
flutter run -d "$MRA_DEVICE" --debug --no-pub \
  --vmservice-out-file="$MRA_RUN/private/vm-uri" \
  > "$MRA_RUN/private/flutter.log" 2>&1
```

Flutter runnerはこのターミナルで動かし続けます。別ターミナルに `MRA_ROOT`、`MRA_RUN`、`MRA_PLATFORM`、`MRA_DEVICE` の値を引き継ぎ、URIファイルが生成された後で実行します。URI本文やraw Flutterログは貼り付けず、シェルトレースも使わないでください。

```sh
cd "$MRA_ROOT/packages/marionette_agent"
MARIONETTE_TEST_PLATFORM="$MRA_PLATFORM" \
MARIONETTE_TEST_DEVICE="$MRA_DEVICE" \
MARIONETTE_TEST_VM_URI_FILE="$MRA_RUN/private/vm-uri" \
MARIONETTE_TEST_EVIDENCE="$MRA_RUN/evidence" \
dart run integration_test/all_commands_smoke.dart
```

開始時のTap countが0である必要があります。再実行は、前のrunnerを `q` で終了し、アプリを新規起動してURIを取り直してから行います。失敗した操作やworkflowの自動再送はしません。

## 確認する内容

「全コマンド」は現在のCLIの全コマンド・サブコマンドを指します。全オプションの組合せ、全端末・OS版、macOS/Web録画の網羅を意味しません。

| コマンド | 合格条件 |
| --- | --- |
| `--help` / `--version` | JSON応答、終了0 |
| `doctor` / `doctor --probe-uri` | 診断の終了0、アプリへの独立probe成功 |
| `connect` | 新規接続と同じURIへの再connectが成功 |
| `session list` / `session show` | 接続前0件、接続後1件、状態照会が成功 |
| `snapshot` | 初期カウンタ0、実ref取得、key filterで1件 |
| `get text` / `get box` / `get count` | 操作後の表示一致、論理座標、snapshotとの件数一致・不存在0件 |
| `is visible` | tapボタンがknown/true |
| `tap` | refと取得bounds中心の座標でカウンタが1回ずつ増加、selectorによるタブ移動 |
| `fill` | ref入力16文字、selectorで3文字へ置換、空文字クリア、再入力 |
| `swipe` | selectorでPage 1→2、取得boundsの幅80%を動かす座標swipeで2→1 |
| `scroll` | 上向き400pxと150pxの2ジェスチャーでBottom reachedに到達 |
| `wait` | ページ・画面要素のexists、About移動後のControlsのgone |
| `screenshot` | PNG、JPEG、注釈PNGが復号可能。別途目視で画面と注釈位置を確認 |
| `logs` | Add log entry操作による `manual log entry added` を取得 |
| `workflow schema` | 全体schemaと6 actionそれぞれのschemaを取得 |
| `workflow validate` | all-actions.yamlの16ステップをbinding込みで検証 |
| `workflow run` | 16ステップ完了、Bottom reached、finalSnapshotのrefを別CLIで使用、カウンタ合計3 |
| `record start` / `record status` / `record stop` | 対象platformで録画継続、MP4確定、stop再実行で同じ成果物。別途動画内容を確認 |
| `close` / `close --all` | 通常close後の再接続、全close後0件、未接続エラー、daemonのsocket/metadata消失 |

エラー系も期待終了コードと正規化コードを照合します。未接続は3/NOT_CONNECTED、古いrefは4/STALE_REF、不存在は4/TARGET_NOT_FOUND、複数一致は4/AMBIGUOUS_TARGETです。binding 0.6.0のidentifier操作は6/UNSUPPORTED_CAPABILITYが期待結果です。拒否されたtapの前後でカウンタが増えないことを確認します。

## 証跡と終了

実行ごとに専用runtimeと `<evidence>/<platform>-<一意名>/` を作成します。`results.json` にコマンド、期待/実終了コード、秘匿した応答・診断、状態検査、失敗理由を保存します。途中失敗でも所有runtimeの `close --all` と記録保存を試み、失敗時は終了1になります。runtimeは診断用に保持します。

画像はinitial、initial-annotated、initial-jpeg、filled-page-two、scrolled、workflow-bottom、aboutです。`operations.mp4` はUI操作からworkflow完了までを含みます。スクリプトのPASSはCLIと状態の自動照合が通ったことを示します。画像を開き、動画を再生または時系列フレームに復号して、入力・Page 2・スクロール・タブ遷移と注釈の位置を目視確認してください。結果JSONの `visualReview` は、その追加確認前であることを示します。

最後にrunnerのターミナルで `q` を入力してアプリを終了し、自分で起動した端末を停止します。record/session/daemon/runner/appが残っていないことを確認してから、URIファイルを削除し、端末を解放してください。

```sh
rm "$MRA_RUN/private/vm-uri"
# 自分が起動した端末だけを停止:
# xcrun simctl shutdown "$MRA_DEVICE"  # iOS
# adb -s "$MRA_DEVICE" emu kill       # Android
```

実施結果は [iOS/Android検証記録](../../docs/verification/all-commands-ios-android.md) を参照してください。
