# workflowファイル実行仕様 v1

本書は、`marionette-agent`に実装されているworkflow v1の入力、検証、実行、出力を定義します。workflowのdocument schema versionは1、公開結果の`schemaVersion`は1、daemonとのIPC `protocolVersion`は4です。

利用者向けのCLI全体は[CLIリファレンス](cli-reference.ja.md)、通常コマンドを含む製品契約は[製品仕様](../SPEC.md)、内部構成は[アーキテクチャ](../ARCHITECTURE.md)、コマンドhandlerの実装境界は[コマンド実装契約](command-contract.ja.md)を参照してください。

## 機能の範囲

workflowは、JSONまたは制限付きYAMLで定義したUI処理を、接続済みの1 sessionで記述順に実行します。v1で使用できるactionは次の6種類です。

```text
snapshot / tap / fill / swipe / scroll / wait
```

workflow全体はdaemonへの1要求であり、完了まで同じsessionのqueueを占有します。同じsessionの別要求がstep間へ割り込むことはありません。異なるsessionの要求は並行実行できます。

最初の失敗で停止します。完了済みstepのrollback、失敗stepのretry、途中再開、workflow全体の自動再実行は行いません。workflowはdatabase transactionでも冪等処理でもありません。

v1には次を含みません。

- 条件分岐、loop、並列step。
- shell、Dart、JavaScriptの実行。
- 別workflowのincludeやcall。
- `connect`、`close`、`session`など接続寿命の操作。
- workflow内の`@e1`形式のref。
- 座標tap、座標swipe。
- screenshot、logs。

## CLI

### schemaを取得する

```sh
marionette-agent workflow schema --json
marionette-agent workflow schema tap --json
```

引数なしではworkflow全体のJSON Schema Draft 2020-12を返します。actionを指定すると、そのstepと必要な`$defs`だけを含む単独で解決可能なschemaを返します。指定できるactionは`snapshot`、`tap`、`fill`、`swipe`、`scroll`、`wait`です。未知のactionは`INVALID_ARGUMENT`になります。

schemaはDart定数としてCLIへ同梱され、外部fileやnetworkを読みません。session接続、runtime directory、daemonも必要ありません。

成功時の`data`は次の形です。`action`は全体schemaなら`null`、個別schemaなら指定名です。

```json
{
  "workflowSchemaVersion": 1,
  "action": "tap",
  "schema": {}
}
```

### fileを検証する

```sh
marionette-agent workflow validate ./flow.yaml --json
marionette-agent workflow validate ./flow.json --check-inputs --json
marionette-agent workflow validate ./flow.json \
  --inputs ./inputs.json --json
marionette-agent workflow validate - --format json --json < ./flow.json
```

`validate`はアプリへ接続せず、syntax、YAML subset、schema、意味制約、size上限を検証します。UI要素の存在、一意性、可視性、backend capabilityは実行時に確認します。runtime directoryとdaemonは作成しません。

既定はtemplate検証です。`required:true`のinputや、defaultを持たない参照inputの値が未指定でも成功します。`--inputs <path>`または`--check-inputs`を付けるとbindingまで検証します。`--check-inputs`だけの場合は、空objectをinputsとして扱います。

成功時の`data`は次の形です。

```json
{
  "workflow": "fill-input",
  "format": "json",
  "stepCount": 2,
  "mode": "template",
  "requiredInputs": ["value"],
  "inputsValidated": false
}
```

`requiredInputs`は、外部値が必要なinput名を辞書順で返します。`required:true`の定義と、stepから参照されdefaultを持たない定義が対象です。binding検証時は`mode:"bound"`、`inputsValidated:true`になります。

### workflowを実行する

```sh
marionette-agent --session demo workflow run ./flow.yaml --json
marionette-agent --session demo workflow run ./fill.json \
  --inputs ./private-inputs.json --json
```

`run`は選択sessionが事前に`connect`済みであることを要求し、暗黙に接続しません。CLIはfileをparseして全件検証し、正規化したworkflowとinputsをdaemonへ送ります。daemonも同じschemaと意味制約を再検証してからUIへアクセスします。`run`は常にbinding検証を行うため、`--check-inputs`は指定できません。

全体の`--timeout`は既定30,000 msです。CLI処理開始時からの絶対deadlineであり、workflowとinputsの読込、parse、検証、daemon起動済み確認、queue待ち、全stepを含みます。stepごとに全体deadlineを更新しません。daemonの確定済みtimeout結果を受け取るため、IPC受信だけにはdeadline後最大250 msのtransport猶予があります。この猶予でbackendの実行期限は延長しません。

## fileとformat

`validate`と`run`はworkflow pathを正確に1つ要求します。

| オプション | 動作 |
| --- | --- |
| `--format json\|yaml` | workflowのformatを明示する。拡張子より優先 |
| `--inputs <path>` | input値を持つJSONまたはYAML objectを読む |
| `--inputs-format json\|yaml` | inputsのformatを明示する。`--inputs`指定時だけ使用可能 |
| `--check-inputs` | 空objectまたは指定inputsでbindingを検証する。`validate`専用 |

明示しないformatは`.json`、`.yaml`、`.yml`から判定します。stdinの`-`または未知の拡張子では、対応する`--format`か`--inputs-format`が必須です。workflowとinputsの両方を同時にstdinから読むことはできません。

相対pathはCLIを実行したcurrent working directory基準です。URL、環境変数、command substitution、includeを展開しません。path指定では通常fileだけを受理し、FIFO、socket、device、directoryなどは開く前に`INVALID_ARGUMENT`とします。存在しないfileや読込失敗は`IO_ERROR`です。

stdinはredirectされている必要があります。TTYからの対話入力は要求せず、EOFまたはdeadlineまで読みます。

入力はUTF-8です。先頭のBOMは受理します。空または空白だけの入力は`INVALID_ARGUMENT`です。syntax errorやYAML warningのsource excerpt、file内容はerrorへ含めません。

## workflow document

JSONが正規data modelです。top-levelはobjectで、次のfieldを持ちます。

| field | 型 | 必須 | 制約 |
| --- | --- | --- | --- |
| `schemaVersion` | integer | 必須 | `1`だけを受理 |
| `name` | string | 必須 | `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` |
| `description` | string | 任意 | 最大256 Unicode scalar |
| `inputs` | object | 任意 | input定義。最大32件 |
| `steps` | array | 必須 | 1〜100件。配列順に実行 |

すべてのobjectはclosed schemaです。定義されていないfieldを拒否します。stepの`id`はworkflow内で一意でなければなりません。

### 例: 画面を移動してsnapshotを返す

同梱例の[reach-controls.yaml](../../packages/marionette_agent/examples/workflows/reach-controls.yaml)は、動作確認アプリでタブ移動、待機、swipe、snapshotを順に実行します。

```yaml
schemaVersion: 1
name: reach-controls
steps:
  - id: open-about
    action: tap
    target: {key: about_tab}
  - id: wait-about
    action: wait
    target: {key: about_content}
    state: exists
  - id: open-controls
    action: tap
    target: {key: controls_tab}
  - id: wait-controls
    action: wait
    target: {key: text_input}
    state: exists
  - id: next-page
    action: swipe
    target: {key: page_view}
    direction: left
    distance: 300
  - id: inspect-controls
    action: snapshot
```

[reach-controls.json](../../packages/marionette_agent/examples/workflows/reach-controls.json)は同じ内容のJSON版です。

## input定義とbinding

v1のinput型はstringだけです。

| field | 型 | 必須 | 動作 |
| --- | --- | --- | --- |
| `type` | string | 必須 | `"string"`だけを受理 |
| `required` | boolean | 任意 | 既定`false`。外部値の明示指定を要求 |
| `default` | string | 任意 | 外部値がなければ使用 |
| `sensitive` | boolean | 任意 | 既定`false`。`true`ならdefaultを禁止 |

input名は`^[A-Za-z][A-Za-z0-9_]{0,63}$`です。inputs fileは宣言済みinput名からstring値へのobjectでなければなりません。未宣言field、`null`、number、boolean、object、arrayは拒否し、stringへ暗黙変換しません。空文字は有効です。

解決順序は外部値、defaultの順です。次の組み合わせはtemplate検証の時点で拒否します。

- `required:true`と`default`の併用。
- `sensitive:true`と`default`の併用。
- stepから参照するinputが未宣言。

`required:true`は、stepで参照しない場合も外部値を要求します。任意inputでも、stepから参照されdefaultがなければbinding時に外部値を要求します。任意かつ未参照でdefaultもないinputは、値を省略できます。

文字列の部分展開はありません。fillの`text`は次のいずれか正確に1つです。

```json
{"literal":"固定文字列"}
```

```json
{"input":"宣言済みinput名"}
```

同梱の[fill-input.json](../../packages/marionette_agent/examples/workflows/fill-input.json)と[inputs.example.json](../../packages/marionette_agent/examples/workflows/inputs.example.json)にbinding例があります。

## step

すべてのstepは次の共通fieldを持ちます。

| field | 型 | 必須 | 制約 |
| --- | --- | --- | --- |
| `id` | string | 必須 | workflow内で一意。`^[A-Za-z][A-Za-z0-9_-]{0,63}$` |
| `action` | string | 必須 | 6種類のactionのいずれか |

actionごとに許可されたfield以外は指定できません。

### target

`tap`、`fill`、`swipe`、`scroll`、`wait`は`target`を必須とします。次の4形状のうち正確に1つを指定し、値は空文字以外のstringとします。

```yaml
target: {key: save_button}
target: {identifier: save-button}
target: {text: Save}
target: {type: ElevatedButton}
```

照合は完全一致です。固定binding 0.6.0は`identifier` selectorをサポートしないため、そのtargetを含むworkflowはUIへアクセスする前に`UNSUPPORTED_CAPABILITY`になります。

workflowでrefを受理しないのは、refが実行時の公開snapshotで生成され、snapshot更新やmutationで失効するためです。座標操作も受理しません。

### `snapshot`

追加fieldはありません。backendを観測し、sessionの公開snapshotを更新してrefを発行します。

workflow内で最後に取得し、完了時にも有効なsnapshotだけが`finalSnapshot`候補になります。後続の`tap`、`fill`、`swipe`、`scroll`は候補を破棄します。後続の`wait`は公開snapshotも候補も変更しないため、`snapshot`の後が`wait`だけならそのsnapshotを返せます。

### `tap`

`target`を1つ必須とします。通常の要素tapと同じ再観測、一意性検証、ref失効、1回送信の契約を使います。

### `fill`

`target`と`text`を必須とします。入力欄の値を置き換え、空文字ならclearします。`text`は`literal`または`input`の排他的なobjectです。

### `swipe`と`scroll`

`target`と`direction`を必須、`distance`を任意とします。

| field | 型 | 制約 |
| --- | --- | --- |
| `direction` | string | `left`、`right`、`up`、`down`。指の移動方向 |
| `distance` | number | 有限の正数。既定200 logical pixel |

`scroll`も現在は同じswipe primitiveを使用します。成功はgesture処理の完了であり、画面遷移、scroll量、対象contentへの到達を保証しません。必要なら後続の`wait`や`snapshot`で確認します。

### `wait`

`wait`はworkflow専用のread-only actionです。UI操作をretryせず、`inspect`をpollします。

| field | 型 | 必須 | 制約 |
| --- | --- | --- | --- |
| `target` | object | 必須 | selectorを1つ |
| `state` | string | 必須 | `exists`または`gone` |
| `timeoutMs` | integer | 任意 | 1〜30,000。既定5,000 |
| `pollIntervalMs` | integer | 任意 | 50〜1,000。既定100 |

最初の`inspect`は即時に行います。条件を満たさない場合は、前回の`inspect`完了から`pollIntervalMs`後に次を実行し、並行pollは行いません。step期限は、step開始時刻に`timeoutMs`を足した時刻とworkflow全体deadlineの早い方です。

`exists`の判定は次のとおりです。

- 一致が正確に1件で、`visible != false`なら成功します。visibility不明は成功可能として扱います。
- 2件以上なら直ちに`AMBIGUOUS_TARGET`です。非表示要素も一致数に含めます。
- 0件または唯一の一致が`visible:false`ならpollを続けます。

`gone`は一致が0件なら成功し、1件以上ならpollを続けます。複数一致でも`AMBIGUOUS_TARGET`にはしません。

text selectorでは、表示textが一致してもbackend matcherとの対応を確認できない唯一の要素なら、`exists`と`gone`のどちらも`UNRESOLVABLE_TARGET`です。安全性を確認できない表示textを`gone`へ誤変換しません。未知のtext由来を含めて複数一致する`exists`は`AMBIGUOUS_TARGET`です。

waitはmutationを送信せず、公開refを発行・失効しません。条件が期限内に成立しなければ`TIMEOUT / not_sent`でworkflowを停止し、現在の接続世代とrefを破棄します。独立したtop-levelの`wait`コマンドはありません。

## JSONとYAMLの受理範囲

JSONとYAMLは、正規化後に同じJSON data model、schema validator、`WorkflowPlan`を通ります。

JSONではduplicate keyをdecode前に検出します。escape表現後に同じkeyになる場合も重複です。trailing comma、非有限number、不完全なsyntaxを拒否します。

YAMLは1.2の単一documentによる安全なsubsetです。

- mapping keyはstringだけで、duplicate keyを拒否します。
- 値は`null`、boolean、有限number、string、sequence、mappingだけです。
- tag、custom tag、anchor、alias、merge key、複数documentを拒否します。
- 1.1など異なるversion directiveと未知directiveを拒否します。
- timestamp風のscalarをprocessor固有型へ変換せずstringとして扱います。
- parse後に通常の`Map<String, Object?>`と`List<Object?>`へ再帰copyし、共有nodeを残しません。

## sizeと構造の上限

| 対象 | 上限 |
| --- | --- |
| workflow入力file / stream | UTF-8で1 MiB |
| inputs入力file / stream | UTF-8で1 MiB |
| 正規化後のworkflow / inputs | JSON encode時にそれぞれ1 MiB |
| 入れ子 | object / arrayで最大32段 |
| step数 | 1〜100 |
| input定義数 | 最大32 |
| `description` | 最大256 Unicode scalar |
| input値、default、fill literal | UTF-8で各64 KiB |
| 展開後のIPC params / step params | JSON encode時に8 MiB |
| IPC frame | 改行を含め64 MiB |

integer fieldへ小数は指定できません。すべてのnumberは有限でなければなりません。上限はCLIとdaemonのうち該当する両境界で検証します。

## 実行意味論

`run`は次の順序で処理します。

1. CLIが絶対deadline内でworkflowを読み、parseします。
2. CLIがtemplate全体を検証します。
3. CLIがinputsを読み、bindingと全stepを検証します。
4. CLIが正規化済みの`{"workflow":object,"inputs":object}`を1 IPC requestで送ります。
5. daemonが両object、全step、binding、上限を再検証します。
6. daemonが接続済みsessionを確認し、plan内の全selector capabilityを検証します。
7. 同じsessionのqueueを保持したまま、各stepを記述順に1回ずつ実行します。
8. 最初の失敗で後続stepを送信せず終了します。
9. 成功時、まだ有効なworkflow内snapshotがあれば`finalSnapshot`として返します。

後半stepのschema errorや非対応selectorも、最初のUI read / mutationより前に検出します。この場合、`completedSteps`は0で失敗stepは未開始です。

内部では、workflow全体の`WorkflowExecution`が開始時のsession identity、接続epoch、deadline、停止状態、進捗、snapshot候補を所有します。各stepには新しい`Execution`を作り、通常コマンドと同じ1 step 1 mutationの制約を維持します。stepから`SessionManager.handle`を再帰呼び出ししません。

すべての`await`前後と結果公開前に、親の停止状態、開始epoch、deadlineを確認します。timeoutや切断で古い接続世代を停止した後にbackend Futureが完了しても、後続step、進捗、ref、再接続後の状態を変更できません。

## snapshotと後続CLI

共通の`--content-boundaries`と`--max-output`は`finalSnapshot`にも適用します。境界と件数metadataはそのsnapshot object内に置き、省略されたrefは使用できません。文字数予算とidle終了後の再接続は[CLIリファレンス](cli-reference.ja.md#未信頼コンテンツと出力量)に従います。

成功結果に`finalSnapshot`がある場合、その返却されたrefはsessionの最新公開snapshotとして残ります。別CLI processの通常コマンドへ渡せます。

```sh
marionette-agent --session demo workflow run ./flow.yaml --json
# finalSnapshotで返された実際のrefを使用する
marionette-agent --session demo fill @e57 'workflowの続き' --json
```

queueを解放した後の独占は保証しません。workflow完了後、別要求が先にsnapshot、mutation、close、reconnectを行えば返却refは失効します。後続コマンドが`STALE_REF`を返した場合は、workflow成功を取り消したり再実行したりせず、新しいsnapshotを取得します。

workflow開始前にsessionへ保存されていたsnapshotを`finalSnapshot`として流用しません。失敗時も`finalSnapshot`を返しません。

## 成功結果

成功時は通常の結果envelopeの`data`へ次を返します。

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "demo",
  "data": {
    "workflow": "reach-controls",
    "completedSteps": 6,
    "requiresSnapshot": false,
    "finalSnapshot": {
      "generation": 42,
      "elements": [
        {
          "ref": "@e57",
          "type": "TextField",
          "key": "text_input",
          "visible": true
        }
      ]
    }
  },
  "error": null
}
```

`completedSteps`は成功確定したstep数です。`requiresSnapshot`は常に含まれ、`finalSnapshot`を返せる場合は`false`、それ以外は`true`です。個々のaction結果や中間snapshotは返しません。workflow document、inputs object、展開済みfill入力も返しません。

text modeではworkflow名と完了step数を表示し、`finalSnapshot`があれば通常のsnapshot形式で続けます。なければ`snapshot`の実行を案内します。

## 失敗結果とoutcome

失敗時は通常の`AgentError`へ進捗`details`を追加します。

```json
{
  "schemaVersion": 1,
  "ok": false,
  "session": "demo",
  "data": null,
  "error": {
    "code": "TARGET_NOT_FOUND",
    "message": "Workflow step failed",
    "hint": "Inspect the current UI; completed steps must not be replayed automatically",
    "outcome": "not_sent",
    "details": {
      "workflow": "reach-controls",
      "progressKnown": true,
      "stepIndex": 2,
      "stepId": "open-controls",
      "action": "tap",
      "completedSteps": 1
    }
  }
}
```

`stepIndex`は1始まりです。`completedSteps`は先頭から成功確定したstep数です。`outcome`はworkflow全体ではなく、失敗したstepのUI mutation送信状態を表します。

| 停止状況 | outcome | 接続状態 |
| --- | --- | --- |
| CLI / daemon検証、未接続、queue待ちtimeout | `not_sent` | UIへ未送信。既存状態を維持 |
| 対象なし、曖昧、解決不能、非対応selector | `not_sent` | mutation前なら接続を維持 |
| mutationの確定したbackend失敗 | `failed` | 接続を維持。refは失効済み |
| mutation送信後のtimeout、切断、未分類失敗 | `unknown` | 接続とrefを破棄 |
| snapshot / waitのread中timeoutまたは切断 | `not_sent` | 接続とrefを破棄 |
| wait条件timeout | `not_sent` | 接続とrefを破棄 |

step開始前の検証、未接続、queue timeout、全selector capability検証では、`stepIndex`、`stepId`、`action`は`null`、`completedSteps`は0です。workflow名を安全に読めた場合だけ`workflow`へ含めます。

daemonへ要求を送った後に応答を確実に受信できなかった場合、実行中stepを推測しません。`outcome:"unknown"`、`progressKnown:false`とし、`completedSteps`、`stepIndex`、`stepId`、`action`は`null`です。IPC frameのsize超過など、実行は完了したが結果を配送できない場合も同じです。UI操作を自動再送してはいけません。

通常のtext出力でも、進捗が既知なら完了step数と失敗stepを表示し、不明なら`Workflow progress unknown`と表示します。

## 秘匿契約

workflow本体、inputs、解決済みparams、`fill`入力を成功報告、error message、diagnosticへ複写しません。利用者が付けたworkflow名とstep IDは、schemaで安全な文字列に制限したうえで実行結果にだけ含めます。

`sensitive:true`はdefault埋込みを禁止するmetadataです。値の追跡、保存、置換、snapshot maskは行いません。入力値またはアプリが加工した値が画面に表示され、後続snapshotが観測した場合、その値は`finalSnapshot`を含むstdoutへ現れる可能性があります。

秘密値は権限を限定したinputs fileかstdinで渡してください。workflow本体へliteralとして書かれた値が秘密かどうかをCLIは判定できません。

## 実装と検証の参照先

実装の正本は次のfileです。

- [schema_catalog.dart](../../packages/marionette_agent/lib/src/workflow/schema_catalog.dart): 同梱JSON Schema。
- [workflow_loader.dart](../../packages/marionette_agent/lib/src/cli/workflow_loader.dart): file、JSON、YAML subset。
- [model.dart](../../packages/marionette_agent/lib/src/workflow/model.dart): 意味検証、binding、実行plan。
- [workflow_runner.dart](../../packages/marionette_agent/lib/src/workflow/workflow_runner.dart): queue内のstep実行と結果。
- [wait.dart](../../packages/marionette_agent/lib/src/commands/wait.dart): wait条件。

契約は次のtestで固定されています。

- [workflow_model_test.dart](../../packages/marionette_agent/test/workflow_model_test.dart): schema、input、上限、JSON/YAML。
- [workflow_cli_test.dart](../../packages/marionette_agent/test/workflow_cli_test.dart): CLI、stdin、deadline、IPC配送。
- [workflow_execution_test.dart](../../packages/marionette_agent/test/workflow_execution_test.dart): queue、step、wait、ref、outcome。
- [review_safety_test.dart](../../packages/marionette_agent/test/review_safety_test.dart): text照合と配送安全性。
