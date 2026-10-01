# workflowファイル仕様 v1

[English](../workflow-file-spec.md) · [日本語の目次](README.md)

実行の始め方とダウンロード例は[workflowガイド](https://r0227n.github.io/marionette_agent/ja/guides/workflows/)に集約しました。本書はschemaVersion 1の詳細な入力・実行・結果契約です。公開結果のschemaと内部IPCのversionは別物です。現行IPCの値は[protocol.dart](../../lib/src/protocol/protocol.dart)を参照してください。

<a id="validation"></a>
## ローカル検証とbinding

schema/validateは接続・daemon・runtime directoryなしで実行します。schemaは同梱のJSON Schema Draft 2020-12を返し、外部file/networkを読みません。action指定時はそのstepと必要な`$defs`を含む単独schemaを返します。結果dataは`{workflowSchemaVersion:1,action,schema}`で、全体schemaのactionはnullです。

validateの既定はtemplate検証です。`--inputs`または`--check-inputs`を付けるとbindingも検証し、check-inputsだけなら空objectを使います。結果は`workflow/format/stepCount/mode/requiredInputs/inputsValidated`です。modeはtemplateまたはbound、requiredInputsは必要な外部input名の辞書順です。対象の存在・一意性・可視性・capabilityは実行時に検証します。

runは常にbindingを検証するためcheck-inputsは指定できません。事前にconnectしたsessionが必要です。CLIで全件検証してから正規化したworkflowとinputsを1要求で送り、daemonでも同じschemaと意味制約を再検証します。

<a id="files"></a>
## file、format、parser

workflow pathは正確に1つです。formatは明示`--format json|yaml`を優先し、未指定なら`.json/.yaml/.yml`で判定します。inputsも同様に`--inputs-format`を使います。未知拡張子とstdin `-`には明示formatが必要です。inputs-formatだけの指定、workflowとinputs両方のstdinは拒否します。

pathはcwd相対で、URL・環境変数・command substitution・includeは展開しません。通常file以外は開く前にINVALID_ARGUMENT、存在しないfileと読込失敗はIO_ERRORです。stdinはredirectが必要で、EOFまたは期限まで読みます。UTF-8の先頭BOMは受理し、空・空白だけは拒否します。parserのsource excerptやfile内容をエラーへ含めません。

JSONはescape後に同名となるduplicate key、trailing comma、非有限number、不完全構文を拒否します。YAMLは1.2単一documentのsubsetで、string key、null、boolean、有限number、string、sequence、mappingだけを受理します。duplicate key、tag、anchor、alias、merge key、複数document、異なるversion/未知directiveは拒否します。timestamp風scalarはstringとして扱います。parse後は通常のMap/Listへcopyし、共有nodeを残しません。

<a id="document"></a>
## documentとstepのfield

すべてのobjectはclosed schemaです。未知fieldとinteger fieldの小数を拒否します。

| Document field | 型・制約 |
| --- | --- |
| schemaVersion | 必須integer、1のみ |
| name | 必須string、`^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` |
| description | 任意string、最大256 Unicode scalar |
| inputs | 任意object、最大32定義 |
| steps | 必須array、1〜100件、記述順 |

全stepに一意のid（`^[A-Za-z][A-Za-z0-9_-]{0,63}$`）とactionが必要です。

| Action | 追加field |
| --- | --- |
| snapshot | なし |
| tap | target |
| fill | target、text |
| swipe / scroll | target、direction、任意distance |
| wait | target、state、任意timeoutMs/pollIntervalMs |

targetはkey/identifier/text/typeのどれか1つを持つobjectで、値は空でないstring、照合は完全一致です。binding 0.6.0のidentifierは非対応で、含まれていれば最初のUIアクセス前にUNSUPPORTED_CAPABILITYです。ref、座標操作、snapshot filterはv1にありません。条件分岐、loop、並列、shell、include、接続寿命操作、screenshot、logsもありません。

swipe/scrollのdirectionはleft/right/up/downで指の移動方向です。distanceは有限の正数、既定200 logical pixelsです。scrollは同じswipe primitiveを使います。成功はgesture処理完了で、到達位置を保証しません。

<a id="inputs"></a>
## input定義

input名は`^[A-Za-z][A-Za-z0-9_]{0,63}$`です。各定義のtypeは必須でstringのみです。required/sensitiveは任意booleanで既定false、defaultは任意stringです。required:trueまたはsensitive:trueとdefaultの併用はtemplate検証で拒否します。

外部値をdefaultより優先します。required:trueは未参照でも外部値を要求し、任意でも参照されdefaultがなければ外部値が必要です。未宣言input参照はtemplateで拒否します。inputs fileは宣言名からstringへのobjectで、未宣言key・null・number・boolean・object・arrayは拒否し、空文字は受理します。

fillのtextは次のどちらか1つで、部分的な文字列展開はありません。

```json
{"literal":"Example value"}
```

```json
{"input":"value"}
```

[fill-input.json](../../samples/workflows/fill-input.json)と[inputs.example.json](../../samples/workflows/inputs.example.json)に実例があります。

<a id="wait"></a>
## waitの条件と期限

stateは必須のexists/goneです。timeoutMsは1〜30,000（既定5,000）、pollIntervalMsは50〜1,000（既定100）の整数です。最初は即時inspectし、以降は前のinspect完了から間隔を空けます。並行pollはしません。step期限は開始+timeoutMsとworkflow全体deadlineの早い方です。

existsは正確に1件かつvisible != falseで成功し、0件・唯一の非表示は待ちます。複数件は非表示も数えてAMBIGUOUS_TARGETです。goneは0件で成功し、1件以上なら曖昧エラーにせず待ちます。唯一のtext一致の由来がbackend matcherと対応しなければ、exists/goneともUNRESOLVABLE_TARGETです。

waitはUI mutation・公開refの発行・失効を行いません。ただし観測中のtimeout/通信断や条件timeoutでは接続とrefを破棄し、outcome:not_sentになります。queueで開始前に期限切れなら既存状態を維持します。単独waitの期限は共通timeout、stateの既定はexistsで、同じ条件判定を使います。

<a id="limits"></a>
## 上限

| 対象 | 上限 |
| --- | --- |
| workflow入力file/stream | UTF-8で1 MiB |
| inputs入力file/stream | UTF-8で1 MiB |
| 正規化後workflow/inputs | JSON encode時にそれぞれ1 MiB |
| object/arrayの入れ子 | 32段 |
| steps / inputs | 100 / 32 |
| description | 256 Unicode scalar |
| input値、default、fill literal | 各64 KiB UTF-8 |
| 展開後IPC params / step params | JSON encode時に8 MiB |
| IPC frame | 改行込み64 MiB |

数値は有限でなければなりません。CLIとdaemonの該当する両境界で検証します。

<a id="execution"></a>
## queue、deadline、snapshot

workflowは同じsessionのqueueを完了まで占有し、step間に別要求は入りません。異なるsessionは並列実行できます。全体timeoutは既定30,000 msで、file読込・parse・検証・queue待ち・全stepを含み、stepごとに更新しません。確定timeout応答を受信するIPCだけに最大250 msの猶予があり、backend期限は延長しません。

後半stepのschema error、binding、selector capabilityも最初のUIアクセス前に確認します。各stepは新しいExecutionで通常コマンドと同じ1 mutation制約を使います。timeout・切断後の古いFutureは進捗・後続step・再接続後のrefを変更できません。最初の失敗で停止し、rollback・retry・途中再開・全体の自動再実行はしません。

snapshotは公開refを発行します。workflow内の最後のsnapshotが候補となり、後続tap/fill/swipe/scrollで破棄、waitでは保持します。開始前のsnapshotや失敗時のsnapshotは返しません。返したrefはqueue解放後も最新snapshotとして残りますが、別要求のsnapshot/mutation/close/reconnectで失効します。STALE_REFならworkflowを再実行せず観測し直します。

<a id="results"></a>
## 成功・失敗の結果

成功dataは`workflow/completedSteps/requiresSnapshot`と、まだ有効な場合だけ`finalSnapshot`です。finalSnapshotがあればrequiresSnapshot:false、なければtrueです。中間結果・workflow本文・inputs・展開済みfillは返しません。出力予算・境界は[CLIの契約](cli-reference.ja.md#output)に従い、finalSnapshotにも適用します。

失敗の`error.details`は`workflow/progressKnown/stepIndex/stepId/action/completedSteps`です。stepIndexは1始まり、completedStepsは成功確定した先頭step数です。outcomeは失敗stepのmutation送信状態で、先行stepが未実行という意味ではありません。

| 停止状況 | outcome | 状態 |
| --- | --- | --- |
| 検証、未接続、queue期限切れ | not_sent | 既存状態を維持 |
| 対象・capabilityの解決失敗 | not_sent | mutation前なら接続を維持 |
| 確定したbackend mutation失敗 | failed | 接続を維持、refは失効済み |
| mutation送信後のtimeout/切断/未分類失敗 | unknown | 接続とrefを破棄 |
| snapshot/waitのread中timeout/切断、wait条件timeout | not_sent | 接続とrefを破棄 |

step開始前の失敗はstepIndex/stepId/actionがnull、completedSteps:0です。workflow名を安全に読めた場合だけ含めます。daemon送信後に応答を受信できなければprogressKnown:false、outcome:unknownで進捗fieldはnullです。実行完了後のIPC frame超過も結果配送が確定しないため同様です。UI操作を自動再送してはいけません。

<a id="privacy"></a>
## 秘匿と実装の参照先

workflow本文・inputs・解決済みparams・fill入力を診断や実行報告へ複写しません。制約されたworkflow名とstep IDだけを結果に使います。sensitive:trueはdefault埋込みを禁止するmetadataで、値の追跡やsnapshot maskではありません。アプリが表示した値は後続snapshotやfinalSnapshotへ現れる場合があります。秘密値は権限を限定したinputs fileかstdinで渡してください。

- [schema_catalog.dart](../../lib/src/workflow/schema_catalog.dart): 同梱schema。
- [workflow_loader.dart](../../lib/src/cli/workflow_loader.dart): fileとparser。
- [model.dart](../../lib/src/workflow/model.dart): 意味検証とbinding。
- [workflow_runner.dart](../../lib/src/workflow/workflow_runner.dart): 実行と進捗。
- [wait.dart](../../lib/src/commands/wait.dart): 条件判定。
- [workflow_model_test.dart](../../test/workflow_model_test.dart)、[workflow_cli_test.dart](../../test/workflow_cli_test.dart)、[workflow_execution_test.dart](../../test/workflow_execution_test.dart): 境界検証。
