# workflowファイル実行機能 — 実装仕様 v1

状態: workflow v1実装済み。検証結果は[実装・Simulator検証記録](verification/workflow-v1-2026-09-09.md)を参照。
調査日: 2026-09-09

関連文書: [製品仕様](../../../SPEC.md) / [アーキテクチャ](../../../ARCHITECTURE.md) / [実装契約](command-contract.md)

## 別セッションからの実装開始

本書はworkflow v1の入力・実行・出力・検証の正本である。本書内のCLIコマンドは実装済みである。変更を担当する場合は本書とリポジトリのAGENTS.md、関連文書、todo.mdを読む。会話履歴や外部記事の再調査は作業の前提としない。

対象は`packages/marionette_agent/`。Simulator検証用の`example/`は必要に応じて拡張する。隣接リポジトリの変更・path依存・MCP対応は不要。既存単独コマンドは現行契約を維持する。workflow追加に必要な共通基盤変更は本書のExecution設計に従い、Astra担当とする。

仕様書作成の完了と機能実装の完了は分ける。実装時にはtodoへ担当モデル・状態・証跡を記録し、Simulator検証まで終わる前に機能をDONEにしない。

## 結論

JSONまたはYAMLで定型UI操作を定義し、1回のCLI呼び出しで順番に実行した後、最後のsnapshotを通常のCLI操作へ引き継ぐ機能は実装可能である。

推奨する形は、シェル文字列を並べる汎用batchではなく、型付きの線形workflowである。workflow全体をdaemonへの1要求として扱い、同一sessionのキューを完了まで占有する。これにより別プロセスの操作がステップ間へ割り込まず、現在のdeadline、対象解決、ref失効、操作を自動再送しない契約を再利用できる。

実現性は次のとおり。

| 要求 | 判定 | 方針 |
| --- | --- | --- |
| JSONファイルで処理を定義 | 実装可能 | JSONを正規形式とする |
| YAMLファイルで処理を定義 | 実装可能 | JSONへ損失なく変換できる安全なYAML subsetだけを受理する |
| 複数操作を順番に実行 | 実装可能 | 1つのdaemon要求・1つのsessionキュー内で直列実行する |
| ファイル実行後のsnapshotを見て操作を続ける | 実装可能 | 最終snapshotのrefをsessionに残し、次のCLIプロセスから使用可能にする |
| ファイル内でsnapshotのrefを後続操作に固定利用 | 採用しない | ref番号は実行時生成かつ操作後に失効するため、workflow内はselectorを使う |
| 画面内容に応じた分岐・loop | 将来拡張 | 初版は監査しやすく停止性が明確な線形処理に限定する |

## 調査から採用する設計原則

参照記事は、agent向けCLIでは個別flagの組み合わせより構造化payload、実行時schema参照、予測可能な構造化出力が有効だと整理している。[Better Stackの記事](https://betterstack.com/community/guides/ai/cli-gws-ai-agents/)

一次ソースであるGoogle Workspace CLIも、`--params`と`--json`で構造化入力を受け付け、`gws schema`で呼び出し形式を取得し、変更操作の事前確認に`--dry-run`を用意している。また全応答を構造化JSONにしている。[Google Workspace CLI README](https://github.com/googleworkspace/cli/blob/main/README.md#why-gws)、[agent向け利用規約](https://github.com/googleworkspace/cli/blob/main/CONTEXT.md#rules-of-engagement-for-agents)

本CLIのコマンド面は外部Discovery Documentから動的生成されるものではない。そのため動的API探索そのものは模倣せず、次の3点を採用する。

1. workflow入力を型付きobjectに統一する。
2. `workflow schema`で必要な部分だけ機械可読に取得できるようにする。
3. `workflow validate`でUIへ接続せず事前検証できるようにする。

JSON Schemaは構造制約を機械可読に表現でき、2020-12が現行の公開dialectである。[JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12)、[Validation specification](https://json-schema.org/draft/2020-12/json-schema-validation)

YAML 1.2.2のmappingは順序を持たず、keyは一意である必要がある一方、tag、anchor、aliasなどJSONにはない表現も持つ。[YAML 1.2.2 specification](https://yaml.org/spec/1.2.2/) したがって、ステップ順は必ずsequenceで表し、YAML入力はJSON data modelへ安全に正規化できるsubsetへ制限する。Dartでは公式管理の`yaml` packageが単一documentのload APIを提供しているため、parser実装上の障害はない。[Dart yaml package](https://pub.dev/packages/yaml)

隣接する`agent-browser`にも、JSONの文字列配列をstdinから受け取り、複数コマンドを順番に実行するbatch実装がある。[agent-browser batch source](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/cli/src/main.rs#L2059-L2249) ただし本提案は文字列を再parseせず、Marionette固有のselectorとref寿命を型として検証する。

## 目的

- 既知の画面遷移をworkflowファイルへ保存し、agentが毎回0から操作方法を調べるtoken消費を減らす。
- 定型部分を決定的に実行し、未知または可変な部分だけをsnapshotとしてagentへ返す。
- 同じworkflowをJSONとYAMLのどちらでも表現可能にする。
- 単独コマンドと同じsession、deadline、エラー分類、対象の一意性検証、再送禁止を維持する。
- workflow終了時の有効なsnapshot refを、後続の通常CLI呼び出しで利用可能にする。

## 対象外

初版では次を提供しない。

- 条件分岐、loop、並列ステップ。
- 任意shell、Dart、JavaScriptの実行。
- 別workflowのincludeまたはcall。
- `connect`、`close`、`session`などsession寿命の操作。
- workflow内での`@e1`形式のref指定。
- 座標tap、座標swipe。定型処理として画面サイズやlayoutへ依存しやすいため後続候補とする。
- 失敗したUI操作の自動retry、rollback、途中再開。
- screenshot、logsのworkflow組み込み。画像によるIPC上限超過とartifact保存契約を分離して検討する。

## CLI契約

### Schema取得

```sh
marionette-agent workflow schema --json
marionette-agent workflow schema tap --json
```

- session接続とdaemonを必要としない。
- 引数なしではworkflow全体のJSON Schema Draft 2020-12を返す。
- action名を指定すると、そのstep schemaだけを返す。agentは必要なschemaだけ取得できる。
- 出力は既存の結果包絡形式を使い、`session`は`null`とする。
- 成功dataは`{"workflowSchemaVersion":1,"action":null,"schema":{}}`の形とする。`schema`には実際のschemaを入れ、個別取得時の`action`は指定action名にする。未知actionは`INVALID_ARGUMENT`。個別schemaは必要な`$defs`を同梱し単独で解決可能にする。
- 全schemaはversion固定の同梱ファイルから提供する。`required`、`additionalProperties:false`、`oneOf`、数値範囲などを記述する。IDの一意性、input参照整合、UTF-8バイト上限は別の意味検証で実施する。schemaだけで全条件を表せるとは扱わない。

### 事前検証

```sh
marionette-agent workflow validate ./flows/reach-profile.yaml --json
marionette-agent workflow validate - --format json --json < flow.json
```

- session接続とdaemonを必要としない。
- 拡張子`.json`、`.yaml`、`.yml`からformatを判定する。
- pathが`-`の場合、または拡張子から判定できない場合は`--format json|yaml`を必須とする。
- syntax、schema、未知field、step ID重複、input参照、上限を検証する。
- 成功時はworkflow名、format、step数、必要input名を返す。入力全文や`fill.text`は返さない。
- UIの存在やselectorの一意性は実行時にしか検証できない。
- `validate`は既定でtemplate検証のみを行い、必須inputの実値を要求しない。`--inputs <path>`を指定するとbindingまで検証する。`--check-inputs`でもbinding検証を要求でき、その場合`--inputs`省略は空objectとして扱う。
- 成功dataは`{"workflow":"fill-profile","format":"json","stepCount":2,"mode":"template","requiredInputs":["displayName"],"inputsValidated":false}`。binding検証時は`mode:"bound"`、`inputsValidated:true`。`requiredInputs`は外部値が必要なinput名の辞書順配列（requiredまたは参照ありでdefaultなし）。sessionはnull。UI互換性を保証するfieldは返さない。
- JSON/YAML syntax、schema、input不足は`INVALID_ARGUMENT`（exit 2）、fileの読込失敗は`IO_ERROR`（exit 1）とする。エラーへfile内容を含めない。

### 実行

```sh
marionette-agent --session demo workflow run ./flows/reach-profile.yaml --json
marionette-agent --session demo workflow run ./flows/fill-profile.json \
  --inputs ./private/profile-inputs.json --json
```

- 選択sessionが事前に`connect`済みであることを要求する。workflowが暗黙に接続しない。
- `--timeout`はworkflow全体の絶対deadlineであり、ファイル読込、キュー待ち、全stepを含む。
- `--inputs <path>`はJSONまたはYAML objectを読む。workflow pathと同じ拡張子判定規則を使い、workflow pathとinputs pathの両方を`-`にはできない。
- workflowとinputsはdaemonへ送る前にCLI側でparse・検証・正規化する。daemon側でも同じ制約を再検証する。
- 最初の失敗で必ず停止する。continue-on-errorは提供しない。
- workflowは冪等ではない。利用者またはagentが同じworkflowを再実行すると、完了済みstepも再度送信され得る。

### ファイル指定・共通オプション

`validate`と`run`は`<path>`を正確に1つ要求し、`--format json|yaml`、`--inputs <path>`、`--inputs-format json|yaml`を受理する。`--check-inputs`はvalidate専用。formatの明示指定は拡張子より優先する。inputs側のstdinまたは未知拡張子には`--inputs-format`を必須とする。両入力がstdinの要求、重複option、無関係なoptionを拒否する。

相対pathはすべて呼出元cwd基準。URL、include、環境変数の自動展開は行わない。stdinはEOFまで期限付きで読み、端末からの対話入力は要求しない（stdinがTTYなら引数エラー）。読込中もサイズ上限を適用する。`run`は常にbinding検証し、inputs省略を空objectとして扱う。

path入力は通常ファイルを対象とし、FIFO・socket・device等は開く前にINVALID_ARGUMENTとする。ストリームを渡す場合は`-`を使う。通常のテキスト出力でも、実行エラーには完了step数・失敗step ID/index・outcomeを表示し、配送失敗時は進捗不明を明示する。

既存の`--json`は出力指定のまま。入力JSON文字列を受け付けるflagへ転用しない。session名、共通optionの前後配置・重複拒否、timeout既定30,000ms、help/versionの契約を継承する。schema/validateはRuntimeDirectory.prepareも呼ばず、daemon不在で成功する。

## workflow document

### YAML例: 定型画面遷移後にagentへ返す

```yaml
schemaVersion: 1
name: reach-profile-form
description: Profile画面まで移動し、入力欄を観測する
steps:
  - id: open-profile
    action: tap
    target:
      key: profile-tab

  - id: wait-for-form
    action: wait
    target:
      key: display-name-field
    state: exists
    timeoutMs: 5000
    pollIntervalMs: 100

  - id: inspect-form
    action: snapshot
```

実行結果の`finalSnapshot`には有効なrefが含まれる。workflow終了後に別プロセスから続行できる。

```sh
marionette-agent --session demo workflow run ./flows/reach-profile.yaml --json
# finalSnapshotで display-name-field が @e57 だった場合
marionette-agent --session demo fill @e57 'Taro'
marionette-agent --session demo snapshot
```

`@e57`は例であり、ファイルへ固定記述してはならない。

### JSON例: inputを使って定型入力する

```json
{
  "schemaVersion": 1,
  "name": "fill-profile",
  "inputs": {
    "displayName": {
      "type": "string",
      "required": true,
      "sensitive": false
    }
  },
  "steps": [
    {
      "id": "fill-name",
      "action": "fill",
      "target": {"key": "display-name-field"},
      "text": {"input": "displayName"}
    },
    {
      "id": "inspect-result",
      "action": "snapshot"
    }
  ]
}
```

inputsファイル:

```json
{"displayName":"Taro"}
```

文字列展開は`${...}`形式にしない。`{"input":"displayName"}`という型付き参照だけを認め、部分展開、環境変数展開、command substitutionは行わない。literalを使う場合は`"text": {"literal": "Taro"}`とする。`literal`と`input`は排他である。

### Top-level field

| field | 型 | 必須 | 契約 |
| --- | --- | --- | --- |
| `schemaVersion` | integer | 必須 | 初版は`1`のみ |
| `name` | string | 必須 | `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` |
| `description` | string | 任意 | 最大256 Unicode scalar。出力には既定で含めない |
| `inputs` | object | 任意 | input名から定義へのmap。最大32件 |
| `steps` | array | 必須 | 1〜100件。記述順に実行 |

全objectで未知fieldを拒否する。JSON Schemaではobjectが既定で未知propertyを許すため、生成schemaは各objectを閉じる。[JSON Schema object reference](https://json-schema.org/understanding-json-schema/reference/object)

### Input定義

初版のinput型は`string`だけとする。

| field | 型 | 必須 | 契約 |
| --- | --- | --- | --- |
| `type` | string | 必須 | `string`のみ |
| `required` | boolean | 任意 | 既定`false` |
| `default` | string | 任意 | 未指定時に利用 |
| `sensitive` | boolean | 任意 | 既定`false`。`true`ならdefaultとの併用を禁止 |

- input名は`^[A-Za-z][A-Za-z0-9_]{0,63}$`。
- 未宣言input、余分なinput、必須input不足は実行前の`INVALID_ARGUMENT`。
- `required:true`とdefaultの併用はtemplate検証で拒否する。requiredは外部値の明示指定を要求する。任意inputは外部値、defaultの順で解決し、両方なければ未束縛とする。未束縛inputがstepで参照されていればbinding検証で失敗し、未参照なら許容する。空文字は有効な指定値。nullや数値のstringへの暗黙変換は禁止する。
- 入力引数をstdoutの実行報告、stderr、diagnostics、エラーmessageへ複写しない。snapshotの観測内容は次の秘匿範囲に従う。
- sensitive inputをworkflow本体へliteralで書くことはCLIには判定不能である。利用ガイドでは権限を限定したinputsファイルまたはstdinを推奨する。

### 秘匿範囲

`sensitive`はdefaultの埋込みを禁止するmetadataであり、snapshotのマスキング機能ではない。公開snapshotは通常コマンドと同じ観測結果を返すため、入力値やアプリ側で加工された値が画面に表示されればstdoutへ含まれ得る。この制約をhelpと利用ガイドにも記載する。v1では値の置換によるsnapshot改変、秘密値の永続保存・追跡を行わない。

loaderの例外やYAML警告のsource excerpt、展開済みparams、backend例外の全文を出力しない。エラー位置は行・列またはJSON Pointerだけを返す。利用者が付けたname/idも診断へ記録せず、実行報告にのみ含める。

### 共通step field

| field | 型 | 必須 | 契約 |
| --- | --- | --- | --- |
| `id` | string | 必須 | workflow内で一意。`^[A-Za-z][A-Za-z0-9_-]{0,63}$`。ハイフン可 |
| `action` | string | 必須 | `snapshot`、`tap`、`fill`、`swipe`、`scroll`、`wait` |

各stepは`action`に対応するfieldだけを受け付ける。複数actionのfieldを混ぜたobjectはschema errorとする。

### Target

```yaml
target:
  key: save-button
```

`target`は`key`、`identifier`、`text`、`type`のうち正確に1つだけを持つ。空文字は禁止する。JSON Schemaでは排他形状を`oneOf`で表す。[JSON Schema combining reference](https://json-schema.org/understanding-json-schema/reference/combining)

実行時には既存の`SnapshotService.resolve`を使い、0件は`TARGET_NOT_FOUND`、複数件は`AMBIGUOUS_TARGET`、backend非対応selectorは`UNSUPPORTED_CAPABILITY`とする。固定binding 0.6.0では`identifier`が非対応であるという現行制約も維持する。

workflow内でrefを禁止する理由は次のとおり。

- ref番号はdaemon生存中に単調増加し、事前には決められない。
- 現行仕様では新snapshotとUI操作の送信直前に既存refが失効する。
- 静的ファイルへrefを保存すると別sessionまたは別観測世代の要素を指すように見え、安全でない。

### Action別field

#### `snapshot`

追加fieldなし。公開snapshotを取得し、sessionのrefを更新する。

このworkflow内で取得し、完了時にも有効な最新snapshotだけを`finalSnapshot`として返す。実行開始前のsession snapshotを流用しない。後続mutationがあれば候補を破棄し、新snapshotで置き換える。waitは公開snapshotを更新しない。agentへ操作を引き継ぐworkflowはsnapshotを最終stepにする。

queue解放後に別要求の操作・snapshot・closeが実行されると返却refは失効する。次のCLI呼び出しまでの独占は保証しない。後続操作は既存のref再検証を通し、STALE_REFなら新しくsnapshotを取得する。workflow自身の成功と、後続refの成功保証は区別する。

#### `tap`

`target`を必須とする。既存のtarget tapと同じ一意性検証・ref失効・再送禁止を使う。

#### `fill`

`target`と`text`を必須とする。`text`は次のどちらか一方である。

```json
{"literal":"fixed text"}
```

```json
{"input":"declaredInputName"}
```

空文字はclearとして有効。解決後の文字列は最大64 KiBとし、結果や診断へ複写しない。

#### `swipe` / `scroll`

`target`と`direction`を必須、`distance`を任意とする。

| field | 契約 |
| --- | --- |
| `direction` | `left`、`right`、`up`、`down`。指の移動方向 |
| `distance` | 有限の正数。省略時200 logical pixel |

操作結果の成立は保証せず、必要なら後続の`wait`または最終`snapshot`で確認する。

#### `wait`

`wait`はread-onlyの新規primitiveである。UI操作をretryせず、`inspect`だけをpollする。

| field | 型 | 必須 | 契約 |
| --- | --- | --- | --- |
| `target` | object | 必須 | selectorを1つ指定 |
| `state` | string | 必須 | `exists`または`gone` |
| `timeoutMs` | integer | 任意 | 正の整数。既定5,000、上限30,000。workflow全体deadlineを延長しない |
| `pollIntervalMs` | integer | 任意 | 50〜1,000。既定100 |

- 一致は`ElementInfo.value(selector.kind)`で判定する。可視性で除外する前に全一致を数える。`exists`は一致が正確に1件かつ`visible != false`なら成功（不明は現行操作と同じ扱い）。複数一致は直ちに`AMBIGUOUS_TARGET`。0件または唯一の一致が非表示ならpollを続ける。
- `gone`は一致が0件になったとき成功する。1件以上なら期限までpollを続ける。
- step期限またはworkflow全体deadlineの早い方を使う。
- timeout時は`TIMEOUT`、`outcome: not_sent`。待機中にmutationは送信されない。
- pollごとに公開refを発行せず、sessionの現在の公開snapshotを変更しない。
- selector capabilityはpoll前に確認し、非対応なら`UNSUPPORTED_CAPABILITY`。text一致0件で表示用textだけが存在する場合は既存resolveと同じ`UNRESOLVABLE_TARGET`とし、goneの成功に誤変換しない。inspect失敗はそのまま停止する。
- 初回は即時inspect。以後はinspect完了からpollIntervalMs待つ。並行pollはしない。成功条件の判定前にも期限を確認する。waitはworkflow専用actionとして追加し、独立したトップレベルwaitコマンドはv1に含めない。

## YAML受理subset

YAML入力は便利さのために提供するが、内部表現とschemaはJSONを正本とする。

- YAML 1.2の単一documentだけを受理する。
- mapping keyはstringのみ、かつ重複禁止。
- 値はnull、boolean、有限number、string、sequence、mappingのみ。
- custom tag、anchor、alias、merge key、複数documentを拒否する。
- timestampなどprocessor固有の暗黙型へ変換しない。
- parse後に再帰的に通常のDart `Map<String, Object?>` / `List<Object?>`へcopyし、cycleと共有nodeを残さない。
- 入力ファイルはUTF-8、最大1 MiB。BOMは許容する。
- JSONも重複keyを拒否する。通常のdecode後には重複情報が失われるため、token/event段階で検出する。YAMLのtag/anchor/aliasも展開前に拒否する（regexによる文字列走査だけに依存しない）。yaml packageの高水準load APIだけで制限を満たすと仮定せず、token検査を組み合わせる。
- JSON/YAML共通でobject/listの最大入れ子深さ32。workflowとinputs各1 MiB、個々のinput/default/literalはUTF-8で64 KiB以下、展開後IPC paramsは8 MiB以下。CLIとdaemon双方で該当する上限を検証する。非有限数、整数fieldへの小数、範囲外数値は拒否する。

この制限により、同じ意味のJSONとYAMLは同じ正規化objectになり、以降は同じschema validatorとrunnerを通る。

## 実行意味論

1. CLIがworkflowとinputsを期限内に読む。
2. CLIがformat parse、YAML subset検証、JSON Schema相当の検証、input bindingを行う。
3. CLIはtemplateとinputsを1つのIPC requestに載せる。daemonでも全件binding検証してからstepを開始する（wire形状は後述）。
4. daemonが接続済みsessionを確認し、そのsession queueをworkflow完了まで占有する。
5. daemonがstepを記述順に1回ずつdispatchする。
6. 各mutationは既存どおり、対象再観測、ref失効、backendへの1回送信の順で処理する。
7. 失敗時は後続stepを送信せず終了する。
8. 成功時、完了時点で有効な公開snapshotがあれば`finalSnapshot`として返す。

同一sessionへの別要求はworkflow完了後まで待つ。別sessionは従来どおり独立して実行できる。

### timeoutと結果不明

- 全stepはCLIの絶対deadlineを共有する。stepごとにdeadlineをリセットしない。
- backendへ未送信で期限切れなら`TIMEOUT` / `not_sent`。
- 送信後に通信断またはtimeoutが起きたmutationは従来どおり`outcome: unknown`。
- `unknown`を含むすべてのstep失敗でworkflowを停止し、自動再送しない。
- clientが応答待ちを中断しても、daemonはdeadlineまで実行中のbackend callを取り消せない場合がある。この場合も再実行を安全とはみなさない。

outcomeは失敗したstepのUI送信状態を表し、workflow全体が未実行という意味ではない。先行する成功stepは`completedSteps`で別に報告する。完了済みmutationが存在しても、後続waitや対象解決の失敗をfailed/unknownへ昇格させない。

| 停止原因 | outcome | sessionの扱い |
| --- | --- | --- |
| CLI検証失敗・queue待ち期限切れ | not_sent | 変更なし |
| stepの対象なし・曖昧・非対応 | not_sent | 接続維持。mutation送信前なので既存のref規則に従う |
| mutationの確定したbackend失敗 | failed | 接続維持、refは失効済み |
| 送信中mutationのtimeout・通信断・未分類例外 | unknown | 切断・ref失効 |
| read中の通信断・RPC期限超過 | not_sent | 切断・ref失効 |
| waitの条件が期限内に成立しない | not_sent | 条件期限でも全体期限でも切断・ref失効（現行TIMEOUT復旧契約に統一） |
| 実行開始後、次stepに入る前の全体期限切れ | not_sent | 切断・ref失効。次stepを未送信の失敗stepとして報告 |

最後のstep成功確定後は実行を完了済みとする。結果の配送失敗ではその完了を取り消さない。CLIが確かなdaemon結果を受け取れない場合はworkflow全体の進捗不明とする。UI操作の自動再送は行わない。

### 原子性

workflowはdatabase transactionではない。完了済みUI操作をrollbackできず、途中失敗では部分的に画面が変化している可能性がある。

ここで保証する原子性は「同じsessionの別CLI要求がstep間へ割り込まない」ことだけである。Flutter側の観測と操作も現行どおり原子的ではない。

## 出力契約

成功例:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "demo",
  "data": {
    "workflow": "reach-profile-form",
    "completedSteps": 3,
    "requiresSnapshot": false,
    "finalSnapshot": {
      "generation": 42,
      "elements": [
        {
          "ref": "@e57",
          "type": "TextField",
          "key": "display-name-field",
          "visible": true
        }
      ]
    }
  },
  "error": null
}
```

- action成功結果の`requiresSnapshot`をstepごとには返さない。
- intermediate snapshotの全要素を返さない。
- `finalSnapshot`は完了時にまだ有効な場合だけ含める。
- dataに`requiresSnapshot`を必ず含める。finalSnapshotを返せる場合false、それ以外true。`fill`引数やinputs objectは返さないが、snapshotに観測値が含まれ得る。
- text modeでは完了step数と、存在する場合は通常のsnapshot表示を出す。

失敗時はstepで分類したerror code、exit code、outcomeを維持する。どのstepで止まったかを機械判定できるよう、既存error objectへ任意の`details`を追加する。stepIndexは1始まり、completedStepsは成功確定した先頭step数。失敗時にはfinalSnapshotを返さず、現在状態の再観測を促す。復旧hintでworkflow全体の再実行を推奨しない。

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
      "workflow": "reach-profile-form",
      "progressKnown": true,
      "stepIndex": 1,
      "stepId": "open-profile",
      "action": "tap",
      "completedSteps": 0
    }
  }
}
```

`details`へselector値、input値、URIを含めない。成功・失敗の包絡schemaVersionは1を維持する。AgentErrorのtoJson/fromJson/withOutcomeとIPC転送でdetailsを保持し、旧単独コマンドではdetailsを省略する。既存codeのexit mappingを維持する。

step開始前の検証・未接続・queue期限エラーではstepIndex/stepId/actionをnull、completedStepsを0とする（読めたworkflow名だけ含める）。CLIでのsyntax検証は`details.location`として行/列またはJSON Pointerを追加できるがsource excerptを含めない。

IPC送信後に結果が届かなかった場合は、現在のstepを推測しない。`IO_ERROR`または`TIMEOUT`、`outcome:unknown`、`details.progressKnown:false`、completedSteps/stepIndex/stepId/actionはnullとする。daemonから確定結果を受信した場合はprogressKnown:true。送信前の接続失敗はnot_sentで進捗0。UIが動いていない可能性があっても送信後の再送はしない。

## Architecture変更案

```text
workflow file / inputs file
  → CLI WorkflowLoader（JSON/YAML parse、subset制限、template検証・binding事前検証）
  → 1 IPC request
  → daemon session queue
  → WorkflowRunner（線形dispatch、停止、最終snapshot選別）
  → 既存CommandContext / SnapshotService / Backend
```

### CLI層

追加候補:

```text
lib/src/cli/workflow_loader.dart
lib/src/workflow/schema_catalog.dart
lib/src/workflow/model.dart
```

- `workflow schema`と`workflow validate`はdaemonを起動しないspecial commandとしてrunnerで処理する。
- `workflow run`だけをdaemonへ送る。
- `yaml` packageをruntime dependencyへ追加する。
- schemaは実装と同梱し、action codecとの整合を契約testで固定する。外部networkからschemaを取得しない。

### daemon / command層

追加候補:

```text
lib/src/workflow/workflow_runner.dart
lib/src/commands/wait.dart
```

- `SessionManager.handle`へworkflow全体を1要求として渡す。
- `WorkflowRunner`は同じsession queue内で既存handlerを直接dispatchする。`SessionManager.handle`をstepごとに再帰呼び出しすると同一queue待ちでdeadlockし得るため行わない。
- sub-commandは`connect`、`close`、`session`、`workflow`を許可しないallowlist方式にする。
- `wait`は`CommandContext.read`とbackend `inspect`を用い、公開refを生成しない。
- actionのvalidationをworkflow専用に複製せず、可能な範囲で単独CLIと共通のtyped parameter decoderへ抽出する。

### Execution分割（実装必須）

現在の`session/session.dart`のExecutionは`sent`を1つ持ち、mutateの2回目を拒否する。SessionManagerは1queue entryをそのExecution.boundで囲っている。そのまま複数handlerを呼ぶ実装は禁止する。

workflow用には次の2つの寿命を分ける（型名は変更可）。

| 境界 | 所有する状態 | 責務 |
| --- | --- | --- |
| WorkflowExecution | 開始時のsession identity・epoch、全体deadline、cancelled、activeStep、completedSteps、最終snapshot候補 | queueを1回だけ取得。全体終了後の継続・送信を禁止 |
| StepExecution | step専用sent、step deadline、step完了状態、親への参照 | 1step最大1回mutation。現行対象検証・失効・outcome分類を実行 |

各stepで新しいExecutionを作りCommandContextへ渡す。既存の単独コマンドは従来どおり1Execution。workflow dispatchは従来の単独Execution.boundの外側へ分岐し、stepで分類済みのerrorを親のsentで再分類しない。sentの単純resetや2回目拒否の削除は行わない。

全stepは親のsession identityと開始epochへ固定する。再接続後のepochを次stepが取り込み、古いworkflowを続行してはならない。すべてのawait前後、backend送信直前、step開始前に親cancelled・epoch・deadlineを確認する。waitのstep deadlineは開始時刻+timeoutMsと全体deadlineの小さい方、他stepは全体deadline。

step timeoutを返す前に親をcancelし、sessionをdiscardする。Future.timeoutは処理自体を止めないため、遅延完了が後続stepのdispatch、ref公開、completedSteps更新を行わないようにする。停止済みworkflowのcatch/finallyから新しい接続をdiscardしない。親cancelはidempotent、epochが開始時と同じ場合だけdiscardする。全体watchdogとstep timeoutの競合では最初の停止結果を1回だけ確定する。

親の実行ループはstep開始情報を設定→新StepExecutionでhandlerをawait→親の有効性確認→completedSteps加算、を繰り返す。例外では親を終了状態へ移し、後続stepを実行しない。通常の対象エラーでは接続を破棄せずに停止する。キュー解放後にも遅延Futureへ親停止状態が伝わることをテストする。

### IPCと型の対応

IPC commandは`workflow`、paramsは`{"workflow": <正規化template>, "inputs": <供給値object>}`の2fieldのみ。相対path、YAML node、file内容、formatは渡さない。daemonはtemplate/binding/上限を再検証し、全stepを型付きの実行可能planへ変換してからUIへアクセスする。後半stepの型エラーが前半操作後に見つかる設計は禁止する。backend capability検証は接続確認後、最初のstep前にplan全体へ行う。非対応stepがあればcompletedSteps:0で停止する。

| workflow step | 既存handler向けparams |
| --- | --- |
| snapshot | `{}` |
| tap | targetの1fieldをそのまま展開（例:`{"key":"save"}`） |
| fill | targetを展開し`input`に解決済み文字列を追加 |
| swipe / scroll | targetを展開し`direction`と数値`distance`を追加 |
| wait | workflow専用の型付き条件。既存mutation handlerへ渡さない |

metadataのid/actionを個別handlerのparamsへ混ぜない。上流importはbackend adapterだけに置く。snapshot matcherの共通化は可、waitに表示textとの独自照合を実装しない。

新CLIと旧daemonの混在でworkflow/detailsを失わないよう、実装時にIPC protocolVersionを1から2へ上げる。異なるversionは送信前に拒否し、旧CLIでsessionをcloseしてから再connectする案内を返す。daemonを強制終了・自動再実行しない。public schemaVersionとworkflow document schemaVersionはどちらも1のまま。

### 既存契約との関係

- protocol frame上限64 MiBは維持する。workflow fileを1 MiB、stepを100件に制限する。
- 同一sessionの直列化と異なるsessionの独立性を維持する。
- mutationの直前にrefを失効する。
- selectorの一意性と属性検証を既存`SnapshotService`に集約する。
- stdoutは結果だけ、diagnosticsはstderr、入力文字列はdiagnosticsへ出さない。
- workflowは後続機能であり、初版CLIコマンドの意味を変更しない。

## 検証計画

### Unit / contract test

- 同じworkflowのJSON版とYAML版が同一の正規化modelになる。
- 拡張子判定、stdin、`--format`、空file、1 MiB超過を検証する。
- 未知field、型違い、重複step ID、0件／101件stepを拒否する。
- YAMLの重複key、custom tag、anchor、alias、merge、複数document、非string key、非有限numberを拒否する。
- inputの不足、余剰、未宣言参照、default、sensitive default禁止を検証する。
- schemaで受理した各stepがrunnerでも受理され、schemaで拒否した形をdaemonも拒否する。
- workflow内refとsession系commandを拒否する。
- 入力引数が実行報告/診断/errorへ複写されない。別テストで画面に表示された同じ値がsnapshotへ含まれることを確認し、保証範囲を固定する。
- `workflow schema tap`が全schemaより小さく、単独でstep構築に十分な情報を返す。

### Queue / failure test

- 同じsessionへ同時要求しても別要求がworkflow step間へ入らない。
- 別sessionの要求はworkflow中も進行できる。
- 2番目のstep失敗後に3番目のmutationが送信されない。
- backend mutationは各step最大1回だけ呼ばれる。
- 送信前timeoutは`not_sent`、送信後timeout／通信断は`unknown`を維持する。
- waitはinspectだけをpollし、mutationや公開ref発行を行わない。
- intermediate snapshotのrefは後続mutation後に返さない。
- 最終snapshotのrefがworkflow完了後の別CLI要求で使える。
- tap→fill→swipeの3mutationがそれぞれ1回成功し、単独Executionの2回送信ガードも維持される。
- tap成功→対象なしはnot_sentとcompletedSteps:1、tap成功→wait timeoutもnot_sentとcompletedSteps:1。どちらもunknownへ再分類されない。
- 2step目送信中の通信断はunknownとcompletedSteps:1。再connect後に旧Futureが完了しても3step目を送信せず、新接続/refを変更しない。
- template validateは必須値なしで成功し、bound validate/runは同じ入力で不足エラー。required+default、未束縛参照、空文字を検証する。
- 既知結果のdetailsがIPC往復とwithOutcomeで保存される。配送失敗時のprogressKnown:falseと自動再送0回を確認する。
- 後半の無効step・非対応selectorは最初のmutation前に失敗する。
- 最終snapshot後に競合要求が入った場合、後続CLIのrefをSTALE_REFとして拒否する。
- IPC version不一致はUI送信前に拒否される。

### Simulator test

`example`を用いて次を実証し、実行コマンド、期待結果、実結果、画面をtodoの検証記録へ残す。

1. `connect`する。
2. YAML workflowでタブ移動、PageViewまたはscroll、`wait exists`、最終snapshotまで実行する。
3. 最終snapshotのrefを別CLIプロセスの`fill`または`tap`で使用する。
4. 次のsnapshotで画面状態が期待どおり変化したことを確認する。
5. 同じworkflowのJSON版でも同じ到達状態になることを確認する。
6. 不存在selectorで停止し、後続操作が行われていないことを画面で確認する。

コード変更後は開発ガイドどおり`dart format .`、`dart analyze`、関連`dart test`、引き継ぎ時の全体testを実行する。

## 実装単位と完了条件

実装担当はtodoにW01〜W06を登録し、各着手時に実際のモデルを記録する。既存IDと衝突する場合だけ未使用IDへ置換し、本書とtodoの対応を更新する。B07の利用ガイド作業とは変更を調整する。

| ID | 依存 | 完了条件 |
| --- | --- | --- |
| W01 | A06 | 型、loader、JSON/YAML subset、template/binding検証、上限の正常・異常テスト |
| W02 | W01 | 同梱schema、schema/validate CLI、help、文書内例の検証。daemon起動0回 |
| W03 | W01, A07, B01, B02, B03 | 親/step Execution分割、runner、wait、全件事前検証、queue/timeout/遅延応答テスト |
| W04 | W02, W03 | run CLI、protocol 2、details往復、最終snapshot、配送失敗と秘匿範囲のテスト |
| W05 | W04, B06 | exampleでJSON/YAML→snapshot→別CLI操作と異常停止を実証 |
| W06 | W05 | format/analyze/全test成功、同梱例・README・SPEC・ARCHITECTURE・実装契約・todoの整合 |

基盤変更を含むため、担当区分はAstraが妥当である。特にsession queue、protocol error、SnapshotServiceの変更を別モデルの個別commandとして実装しない。

## 引き継ぎ成果物

v1の範囲は本書で確定し、座標操作とscreenshot/logsの組み込みは対象外とする。実装開始のための追加の製品判断は不要。

パッケージにschemaと`examples/workflows/`のJSON/YAML等価なサンプル、inputs例を同梱する。検証では実fixtureのkeyを調べて例を作る。本書のprofile系keyは形式説明用であり、exampleに存在するとは仮定しない。

利用ガイドには接続→schemaまたはtemplate validate→必要値のbinding検証→run→最終snapshot確認→別CLI操作の具体的なコマンドを掲載する。文字入力は既存fillによる置換であり、物理キーボードイベントの新規対応を含めない。

検証記録は`docs/verification/workflow-v1-YYYY-MM-DD.md`に置き、実行コマンド・期待/実結果・環境・画面・残る制約を記載する。token削減率は未計測なので保証しない。定型stepのLLM往復を1回のrunに集約し、必要箇所だけschemaと最終snapshotを読むことで消費を抑える。
