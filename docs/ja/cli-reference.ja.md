# marionette-agent CLI リファレンス

## 基本構文

```text
marionette-agent [共通オプション] <コマンド> [コマンドオプション] [引数]
```

共通オプションはコマンドの前後どちらにも記述できます。同じオプションを複数回指定すると引数エラーになります。

### 共通オプション

| オプション | 既定値 | 説明 |
| --- | --- | --- |
| `--session <name>` | `default` | 操作するsession名。英数字で始まり、英数字・`_`・`-`だけで構成された最大64文字を指定します。 |
| `--json` | 無効 | 成功・失敗とも、stdoutへ結果を1つのJSONオブジェクトとして出力します。シェルスクリプトやagentからの利用に適しています。 |
| `--timeout <ms>` | `30000` | ファイル読込、daemon起動、キュー待ち、接続、処理を含む期限を正の整数のミリ秒で指定します。 |
| `--help`, `-h` | — | ヘルプを表示します。接続は不要です。 |
| `--version` | — | CLIのバージョンを表示します。接続は不要です。 |

```bash
marionette-agent --help
marionette-agent --version
marionette-agent snapshot --session demo --timeout 10000 --json
```

通常のテキスト出力はstdout、診断ログはstderrへ出力されます。`--json`の結果は次の包絡形式です。

```json
{"schemaVersion":1,"ok":true,"session":"demo","data":{},"error":null}
```

オプションではなく文字列として扱いたい引数が`-`から始まる場合は、オプション終端の`--`を置きます。

```bash
marionette-agent --session demo fill --key text_input -- '--not-an-option'
```

## 対象を指定するオプション

要素を操作する`tap`、`fill`、`swipe`、`scroll`では、直近のsnapshotが返したref、または次のselectorオプションのどれか1つだけを指定します。

| 指定方法 | 説明 |
| --- | --- |
| `@e1` | 選択sessionの直近の公開snapshotで発行された短い参照です。番号は実行結果に合わせて置き換えます。 |
| `--key <value>` | Flutter要素のkeyと完全一致させます。通常は最も安定した指定方法です。 |
| `--identifier <value>` | identifierと完全一致させます。固定binding 0.6.0では未対応のため、現在は`UNSUPPORTED_CAPABILITY`になります。 |
| `--text <value>` | 対応する要素型のtextと完全一致させます。表示用Semanticsのtextが常に操作対象になるとは限りません。 |
| `--type <value>` | Flutter要素のtypeと完全一致させます。一意に一致する必要があります。 |

selectorは実行時の観測で一意に一致する必要があります。0件なら`TARGET_NOT_FOUND`、複数件なら`AMBIGUOUS_TARGET`です。新しいsnapshot、再接続、切断、またはUI操作を行うと、それ以前のrefは失効します。UI操作後は再度snapshotを取得してください。

## sessionと接続

### `connect <uri>`

指定sessionを、起動済みFlutterアプリのVM Serviceへ接続します。同じsessionを別URIへ付け替える場合は、先に`close`してください。

```bash
marionette-agent --session demo connect "$VM_URI"
marionette-agent --session demo connect "$VM_URI" --json
```

### `session list`

daemonが保持しているsessionの名前と接続状態を一覧表示します。daemonが起動していない場合も空一覧として成功します。

```bash
marionette-agent session list
marionette-agent session list --json
```

### `session show`

選択sessionの接続状態、秘匿された接続先、snapshotの有効性を表示します。

```bash
marionette-agent --session demo session show
marionette-agent session show --session demo --json
```

### `close`

選択sessionの録画があれば動画を確定し、接続を切断して破棄します。Flutterアプリ自体は終了しません。sessionが存在しない場合も成功します。録画があった場合はdata.recordingに最終状態を返します。

```bash
marionette-agent --session demo close
```

最後のsessionを閉じるとdaemonも終了します。

## 観測

### `snapshot`

現在のUIを観測し、操作可能または可読な要素とrefを返します。これは完全なWidgetツリーではありません。

```bash
marionette-agent --session demo snapshot
marionette-agent --session demo snapshot --json
```

テキスト出力の例です。refが`-`の要素は表示情報としては利用できますが、refによる操作には使えません。

```text
Snapshot 3
@e7 ElevatedButton key="save_button" "Save"
@e8 TextField key="text_input"
- Semantics "Status" (no unique actionable selector)
```

## UI操作

### `tap`

要素または明示座標を1回タップします。

```text
tap <ref>
tap --key|--identifier|--text|--type <value>
tap --x <n> --y <n>
```

`--x`と`--y`は両方が必須で、Flutterの有限かつ非負の論理ピクセルです。要素指定と座標指定は混在できません。

```bash
marionette-agent --session demo tap @e7
marionette-agent --session demo tap --key save_button
marionette-agent --session demo tap --text 'Save'
marionette-agent --session demo tap --x 160 --y 420
marionette-agent --session demo snapshot
```

### `fill`

入力欄の内容を指定文字列へ置き換えます。追記ではありません。空文字列を渡すと入力欄をクリアします。

```text
fill <ref> <text>
fill --key|--identifier|--text|--type <value> <text>
```

```bash
marionette-agent --session demo fill @e8 'こんにちは'
marionette-agent --session demo fill --key text_input 'new value'
marionette-agent --session demo fill --key text_input ''
marionette-agent --session demo snapshot
```

`--text`は入力値ではなく、対象を探すselectorです。実際に入力する文字列は最後の位置引数へ指定します。入力文字列は診断ログへ出力されませんが、アプリが画面へ表示した値は次のsnapshotに含まれる可能性があります。

### `swipe`

要素の中心を起点とする方向指定、または始点・終点を指定した座標方式でスワイプします。

```text
swipe <ref> <left|right|up|down> [--distance <n>]
swipe --key|--identifier|--text|--type <value> <direction> [--distance <n>]
swipe --start-x <n> --start-y <n> --end-x <n> --end-y <n>
```

| オプション | 既定値 | 説明 |
| --- | --- | --- |
| `--distance <n>` | `200` | 要素方式の移動距離。有限の正数をFlutter論理ピクセルで指定します。 |
| `--start-x <n>` | — | 座標方式の始点x。有限の非負数です。 |
| `--start-y <n>` | — | 座標方式の始点y。有限の非負数です。 |
| `--end-x <n>` | — | 座標方式の終点x。有限の非負数です。 |
| `--end-y <n>` | — | 座標方式の終点y。有限の非負数です。 |

座標方式では4オプションがすべて必須で、始点と終点は異なる必要があります。座標方式に対象、方向、`--distance`は指定できません。

```bash
marionette-agent --session demo swipe @e12 left
marionette-agent --session demo swipe --key pager right --distance 240
marionette-agent --session demo swipe \
  --start-x 300 --start-y 400 --end-x 80 --end-y 400
marionette-agent --session demo snapshot
```

`left`などの方向は、コンテンツの移動先ではなく指の移動方向です。コマンド成功はジェスチャー処理の完了を表すだけなので、画面の変化はsnapshotで確認してください。

### `scroll`

指定したスクロール領域を、`swipe`と同じジェスチャー機構で操作します。座標方式はありません。

```text
scroll <ref> <left|right|up|down> [--distance <n>]
scroll --key|--identifier|--text|--type <value> <direction> [--distance <n>]
```

`--distance <n>`の既定値は200で、有限の正数をFlutter論理ピクセルで指定します。

```bash
marionette-agent --session demo scroll --key settings_list up --distance 300
marionette-agent --session demo snapshot
```

方向は指の移動方向です。指定コンテンツへの到達や、画面外要素までの自動スクロールは保証されません。

## 画像とログ

### `screenshot [path]`

現在の画面をPNGとして保存し、保存した絶対パスを返します。pathを省略すると非公開の一時ディレクトリへ保存します。相対pathはコマンドを実行したカレントディレクトリ基準です。

```bash
mkdir -p ./artifacts
marionette-agent --session demo screenshot ./artifacts/screen.png
marionette-agent --session demo screenshot --json
```

既存ファイルは上書きしません。保存先の親ディレクトリは事前に作成してください。複数画像が返された場合は、指定名へ連番を付けて保存します。

### `logs`

bindingが保持している有限範囲のログを取得します。継続購読や無期限の待機は行いません。

```bash
marionette-agent --session demo logs
marionette-agent --session demo logs --json
```

JSONの`data.entries`がログ配列、`data.configured`が収集設定の判定結果です。backendが「未設定」と「0件」を区別できない場合は、`limitation`に制約が返ります。

## workflow

workflowは、JSONまたはYAMLファイルに記述した`snapshot`、`tap`、`fill`、`swipe`、`scroll`、`wait`を順番に実行します。最初の失敗で停止し、成功済みstepのrollbackや自動再実行は行いません。

以下の`packages/marionette_agent/examples/workflows/`を使う例は、リポジトリルートから実行します。

### `workflow schema [action]`

workflow全体、または指定actionのJSON Schemaを返します。接続とdaemonは不要です。`action`には`snapshot`、`tap`、`fill`、`swipe`、`scroll`、`wait`のいずれかを指定できます。

```bash
marionette-agent workflow schema --json
marionette-agent workflow schema fill --json
```

### `workflow validate <path>`

アプリへ接続せずに、workflowファイルの構文、schema、step ID、input参照、サイズ上限などを検証します。UI要素の存在やselectorの一意性は実行時に検証されます。

| オプション | 説明 |
| --- | --- |
| `--format <json|yaml>` | workflowの入力形式を明示します。指定時は拡張子より優先されます。stdinの`-`や未知の拡張子では必須です。 |
| `--inputs <path>` | input値を持つJSONまたはYAML objectを読み、bindingまで検証します。 |
| `--inputs-format <json|yaml>` | inputsの形式を明示します。`--inputs`指定時だけ使用できます。inputsがstdinまたは未知の拡張子なら必須です。 |
| `--check-inputs` | `--inputs`を省略した場合も空objectを使ってbinding検証を行い、必須inputの不足を検出します。`validate`専用です。 |

```bash
marionette-agent workflow validate \
  packages/marionette_agent/examples/workflows/reach-controls.yaml --json

marionette-agent workflow validate \
  packages/marionette_agent/examples/workflows/fill-input.json \
  --inputs packages/marionette_agent/examples/workflows/inputs.example.json \
  --json

marionette-agent workflow validate ./flow.json --check-inputs --json
marionette-agent workflow validate - --format json --json < ./flow.json
```

`--inputs`も`--check-inputs`もない場合はtemplateだけを検証し、必須inputの実値は要求しません。

### `workflow run <path>`

接続済みsessionでworkflowを実行します。workflow全体が同一sessionのキューを占有し、別のCLI要求がstep間へ割り込みません。`--timeout`はファイル読込、キュー待ち、すべてのstepを含む全体期限です。

`run`で使える個別オプションは`--format`、`--inputs`、`--inputs-format`です。意味は`validate`と同じです。`run`は常にbindingまで検証するため、`--check-inputs`は指定できません。

```bash
marionette-agent --session demo workflow run \
  packages/marionette_agent/examples/workflows/reach-controls.yaml \
  --timeout 60000 --json

marionette-agent --session demo workflow run \
  packages/marionette_agent/examples/workflows/fill-input.json \
  --inputs packages/marionette_agent/examples/workflows/inputs.example.json \
  --json

marionette-agent --session demo workflow run ./flow.yaml \
  --inputs - --inputs-format json --json < ./private-inputs.json
```

workflow pathとinputs pathの両方を同時にstdinの`-`にはできません。相対pathはカレントディレクトリ基準で、URL、include、環境変数の自動展開はありません。

最終stepがsnapshotの場合、成功結果の`finalSnapshot`に含まれるrefを次の通常コマンドで使用できます。

```bash
# @e57は例。workflowのfinalSnapshotで返された実際のrefを使用する
marionette-agent --session demo fill @e57 'workflowの続き'
marionette-agent --session demo snapshot
```

失敗時は`error.details.completedSteps`、`stepIndex`、`stepId`を確認します。`outcome: not_sent`は失敗したstepについての状態であり、先行stepまで未実行という意味ではありません。現在の画面をsnapshotで確認し、workflow全体をそのまま再実行しないでください。

## 一連の操作例

次のbash例は、接続、観測、入力、タップ、結果確認、スクリーンショット保存、切断を順に行います。keyは操作対象アプリに合わせて変更してください。

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${VM_URI:?VM_URIを設定してください}"
SESSION='demo'

marionette-agent --session "$SESSION" connect "$VM_URI" --json
marionette-agent --session "$SESSION" snapshot --json
marionette-agent --session "$SESSION" fill --key text_input 'Hello Marionette' --json
marionette-agent --session "$SESSION" snapshot --json
marionette-agent --session "$SESSION" tap --key tap_button --json
marionette-agent --session "$SESSION" snapshot --json
mkdir -p ./artifacts
marionette-agent --session "$SESSION" screenshot ./artifacts/final.png --json
marionette-agent --session "$SESSION" close --json
```

## 終了コードと復旧

| 終了コード | 主な意味 |
| --- | --- |
| `0` | 成功 |
| `2` | 引数エラー（`INVALID_ARGUMENT`） |
| `3` | 未接続、session競合、通信断 |
| `4` | 対象なし、曖昧な対象、古いref |
| `5` | timeout |
| `6` | backendまたはbindingの機能不足 |
| `1` | backend、入出力、内部エラーなど |

通信断またはtimeoutでは、操作が送信済みか判断できない場合があります。CLIはUI操作を自動再送しません。`session show`で状態を確認し、必要なら`connect`し直してからsnapshotで現在の画面を観測してください。

```bash
marionette-agent --session demo session show --json
marionette-agent --session demo connect "$VM_URI" --json
marionette-agent --session demo snapshot --json
```

詳細な製品契約は[製品仕様](../SPEC.md)、workflowファイル自体の形式は[workflowファイル実行機能 — 実装仕様 v1](workflow-file-spec.ja.md)を参照してください。

## 端末画面の録画

Flutterアプリだけでなく、キーボードやOS画面を含む端末／ディスプレイ全体を録画します。VM Serviceへのconnectは不要です。録画中でも同じsessionから通常の操作を実行でき、VM Serviceが切断されても録画は継続します。音声は収録せず、OSが保護するコンテンツの収録は保証しません。

```sh
# iOS Simulator: 起動済み端末のUDIDを明示
marionette-agent --session demo record start ./ios.mp4 --platform ios --device <UDID>
# Android: adb devicesに表示されたserialを明示
marionette-agent --session demo record start ./android.mp4 --platform android --device emulator-5556
# macOS: 1=メインディスプレイ
marionette-agent --session demo record start ./mac.mov --platform macos --device 1

marionette-agent --session demo record status --json
marionette-agent --session demo record stop --json
marionette-agent --session demo close
```

上のstartは各環境の例です。同じsessionで同時に実行せず、先にstopしてください。iOSはmacOS/Xcode、Androidはplatform-tools、macOSは実行元アプリの画面収録許可が必要です。iOS実機は未対応です。ホストはmacOSを対象とします。

- `start <path> --platform <platform> --device <id>`: 全引数必須。保存先の親directoryは作成済みである必要があります。相対pathは呼出元cwd基準。iOS/Androidは`.mp4`、macOSは`.mov`を指定します。既存file・directory・symlinkは上書きしません。
- `status`: recordingStateと保存先、対象、開始日時、経過時間、確定後のbytesを返します。録画なしはidleです。停止後もcloseまでは最終状態を参照できます。
- `stop`: 録画停止と動画の確定・回収まで待ちます。重複stopは同じ結果を返します。録画がない場合はidleとして成功します。
- `close`: 録画を確定してsessionを破棄します。確定期限超過時はsessionを保持するため、statusで確認して再度closeできます。録画が失敗していても、最終状態をdata.recordingに含めてsessionを破棄します。

同じdaemon内では1端末につき1録画、1sessionにつき1録画です。競合はSESSION_CONFLICT（終了コード3）。録画専用sessionはsession list/showで接続状態disconnectedとなりますが、録画状態はrecord statusで確認できます。recordはsnapshot/refを変更しません。

`--timeout`はコマンド要求の期限であり録画時間ではありません。開始待ちは最大30秒です。開始がTIMEOUTになった場合も、遅れて生成された録画processの停止と予約回収を継続し、終了確認までは同じ端末で次の録画を開始できません。Androidは標準screenrecordを180秒で自動停止して回収します。自動再開・分割結合はしません。停止要求がTIMEOUT（終了コード5、outcome:unknown）でも動画確定処理は継続するため、record statusで確認してください。停止・保存の確定失敗はoutcome:failedです。

状態はstarting/recording/stopping/stopped/failed、録画なしはidleです。elapsedMsは開始確認から確定までの壁時計経過時間で、動画のメディアdurationではありません。failedにはfailureとrecoveryPathがあり、stagingの動画を復旧できます（破損・未生成の場合を除く）。stop自体は録画失敗を非0で返します。

macOSの標準コマンドにはfirst-frame通知がないため、startは起動後1秒の生存を確認して返します。実際の動画生成はstopで検証します。iOSは最初のフレーム、Androidは動画headerの生成を開始確認に使います。macOSのメインディスプレイ録画は製品CLIで検証済みです。

`--platform web` / `linux` / `windows` はUNSUPPORTED_CAPABILITY（終了コード6）です。未知のplatform名はINVALID_ARGUMENT（終了コード2）になります。未対応platformはdaemon起動前に拒否し、別方式へ自動fallbackしません。後続対応: [Web #16](https://github.com/r0227n/marionette_agent/issues/16)、[Linux #17](https://github.com/r0227n/marionette_agent/issues/17)、[Windows #18](https://github.com/r0227n/marionette_agent/issues/18)。

録画データはdaemon内の内部パッケージが直接保存します。通常終了とSIGINT/SIGTERMは動画を確定しますが、SIGKILLやホスト停止後の自動復元はありません。Androidの画面回転を伴う録画は保証しません。
