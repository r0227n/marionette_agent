# コマンド実装契約

[English](../command-contract.md) · [日本語の目次](README.md)

CLI handlerとbackend adapterを開発するときの境界を説明します。利用方法は[サイト](https://r0227n.github.io/marionette_agent/ja/)、全体契約は[SPEC](SPEC.ja.md)、依存方向は[ARCHITECTURE](ARCHITECTURE.ja.md)を参照してください。versionをここへ複写せず、[pubspec](../../pubspec.yaml)と[protocol定数](../../lib/src/protocol/protocol.dart)を確認します。

<a id="boundaries"></a>
## 実装境界と登録

```text
CliParser / CliCommand
  -> DaemonClient
  -> SessionManager
  -> CommandRegistry
  -> CommandContext
  -> Backend
```

構文は`cli/commands/`とcatalog、共通型は`cli/command.dart`へ置き、通常handlerは`coreCommands()`にも同名で登録します。decodeはArgResultsをstring keyのJSON paramsへ変換します。IPCから直接届く入力もあるため、handlerでも許可field・型・必須・排他を検証します。未知fieldを無視しません。共通optionはroot parserの`cli/common_options.dart`へ集約し、selectorは`addSelectorOptions`、`parseTarget`と共有decodeを使います。

内部handlerは必要なbackend/protocol/commands/snapshot定義を直接importし、CLI/argsや公開barrelには依存しません。外部の組立用は`marionette_agent.dart`から公開します。上流`marionette_mcp/src/`のimportは`backend/marionette_backend.dart`へ限定し、handlerへ生response mapやconnector例外を渡しません。登録の実行可能な例は[probe_cli.dart](../../integration_test/support/probe_cli.dart)です。

recordは共通session queueからRecordServiceとutilへ委譲します。OS画面録画はVM Service接続なしでも動きますが、Flutter描画録画には接続が必要です。OS処理・終了シグナルはutilへ集約し、操作用refや接続世代を変更しません。

<a id="validation"></a>
## mutation前の入力検証

全paramsをmutation経路へ入る前に検証します。RefQueryとSelectorQueryは外部target、ObservedQueryはfindの選択属性を保持する内部型です。外部JSONからObservedQueryを生成しません。ref/selector/座標を混在させず、空selectorを拒否します。

Pointは有限かつ非負、swipe distanceは有限かつ正数（既定200）、座標swipeの始終点は別です。Directionは指の移動方向です。wait pollは50〜1,000 msの整数（既定100）。追加操作は[provider契約](cli-parity.ja.md)に従い、capabilityを操作前に検証します。

<a id="context"></a>
## CommandContextと送信回数

[CommandContext](../../lib/src/commands/command_context.dart)を通してsession状態へアクセスします。

| API | 契約 |
| --- | --- |
| snapshot | 観測し公開snapshotを置換、新refを発行 |
| observeTarget / resolveRead | 共通の一意性・stale検証を使うread |
| performTarget | 再観測・属性検証、ref失効後にcallbackを1回実行 |
| performTargets | 複数対象を同じ観測で検証し、失効後にcallbackを1回実行 |
| uniqueTarget | 一意matcherと選択時属性をObservedQueryへ保持 |
| performCoordinates | 明示座標の操作前にrefを失効 |
| performEffect | 非UI副作用の送信を記録し、refを保持 |
| read / check | await前後と結果公開前にdeadline・接続世代・親停止状態を確認 |
| deadline / session | 共通絶対期限とsession名。URIは公開しない |

1 ExecutionのUI mutationは最大1回で、callbackもbackend primitiveを正確に1回呼びます。handler独自のretry・queue・session作成・ref保存・接続破棄は実装しません。成功はbackend完了であり、画面の期待状態を保証しません。通常mutationはrequiresSnapshot:trueを返します。

<a id="execution"></a>
## session、期限、対象解決

SessionManagerは同じsessionを直列化し、queue待ちも期限に含め、期限切れ要求を後から実行しません。送信前の拒否はnot_sent、確定mutation失敗はfailed、送信後timeout/切断/未分類失敗はunknownです。read中timeout/切断はnot_sentでも接続とrefを破棄します。古いFutureの完了は再接続後の状態を変更できません。

SnapshotServiceはdaemon単位でgenerationとrefを単調増加させ、session間でも番号を再利用しません。非表示はreason:not_visible、安全な一意selectorがない場合はreason:no_unique_supported_selectorで、refを発行しません。binding 0.6.0の操作selectorはkey/text/typeでidentifierは非対応です。text由来を確認する型はText/RichText/EditableText/TextField/TextFormFieldです。

mutation前に再観測し、0件はrefならSTALE_REF、明示selectorならTARGET_NOT_FOUND、複数は非表示も数えてAMBIGUOUS_TARGETです。ref属性変更はSTALE_REF、一意でも非表示やtext由来不明ならUNRESOLVABLE_TARGETです。再観測と操作は原子的ではなく、refから座標へfallbackしません。

<a id="adapter"></a>
## adapter、画像、ログ

Backendの型付きprimitiveとcapability interfaceを使い、上流のSuccessとresponse構造をadapterで検査します。connection_uriはHTTP(S)をWS(S)へ正規化し、接続にはpath/queryを保持、状態表示はhost/port以外を秘匿します。scrollはswipe primitiveを使い、結果にcommand:scrollを付けます。

screenshotはdaemonからbase64 PNGをCLIへ渡し、[artifact_writer.dart](../../lib/src/cli/artifact_writer.dart)で検証、要求形式への変換、排他的保存を行います。PNG/JPEGの品質・path・失敗cleanupは[画像の契約](cli-reference.ja.md#capture)を参照してください。handlerが別の保存規則を実装せず、取得から保存まで元deadlineを使います。

logsはentries、nullableなconfigured、必要時limitationを返します。未設定が観測された場合だけfalseで、不明と空を区別できなければnullです。アプリのログはstdoutの結果であり、診断ではありません。

AgentErrorは安全なcode/message/hint/details/outcomeを返します。終了コードの表は[出力リファレンス](https://r0227n.github.io/marionette_agent/ja/reference/output/)へ集約しています。診断はINFO以上だけをstderrへ送り、認証URIをredact、改行をescapeし、生error・stack trace・入力値を転送しません。

<a id="workflow"></a>
## workflowとwaitの再利用

workflowは1 queue entryを保持し、stepごとにExecution/CommandContextを作ります。stepからSessionManager.handleへ再帰しません。snapshot/tap/fill/swipe/scroll/waitは通常handlerを利用し、outcomeを改変せず進捗を加えます。詳細は[workflow仕様](workflow-file-spec.ja.md)を参照してください。

単独waitとworkflow waitは共通handleWaitを使います。workflow側だけが全体とstepの早い期限を指定します。handlerは全入力とselector capabilityを検査後、read経路でinspectを直列pollし、mutationを送りません。成功はrefを維持し、read中のtimeout/切断は接続世代を破棄します。

<a id="verification"></a>
## 検証

CLI packageでformat、analyze、関連testを実行し、引き継ぎ前には全testを実行します。snapshot/session/transport、feature_commands/swipe/wait、artifact_writer、workflow_executionの各testが対象解決・送信・遅延結果・保存境界を検証します。

```sh
dart format .
dart analyze
dart test
```

CLI機能を追加・変更した場合はexampleをiOS Simulatorで起動し、製品CLIの応答と実画面の変化を確認します。文書更新先は[日英の文書方針](documentation.ja.md)に従います。
