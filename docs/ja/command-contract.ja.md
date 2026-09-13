# コマンド実装契約

本書は、`marionette_agent`へコマンドを追加・変更するときに守る実装契約を、現在のコードに基づいて説明します。利用者向けのCLI構文は[CLIリファレンス](cli-reference.ja.md)、製品全体の契約は[製品仕様](../SPEC.md)、構成と依存方向は[アーキテクチャ](../ARCHITECTURE.md)、workflow固有の契約は[workflow v1仕様](workflow-file-spec.ja.md)を参照してください。

対象バージョンは`marionette_agent 0.0.1`、公開結果の`schemaVersion`は1、IPCの`protocolVersion`は4です。`marionette_mcp`は0.6.0に固定されています。

## 実装境界

コマンド処理は次の境界に分かれます。

```text
CLI引数
  → CliParser / CliCommand（構文解析とIPC paramsへの変換）
  → DaemonClient（1要求をIPC送信）
  → SessionManager（session選択と直列化）
  → CommandRegistry（handler選択）
  → CommandContext（期限、接続世代、ref、送信回数の管理）
  → Backend（型付きMarionette操作）
```

通常のコマンド実装は`package:marionette_agent/marionette_agent.dart`から公開型をimportします。上流の`package:marionette_mcp/src/`を直接importできる製品コードは`lib/src/backend/marionette_backend.dart`だけです。コマンドhandlerは上流のresponse mapやconnector例外を扱いません。

主な依存の用途は次のとおりです。

| パッケージ | 用途 |
| --- | --- |
| `args` | オプション、サブコマンド、`--`、usage |
| `collection` | 観測属性の構造比較 |
| `path` | pathの正規化と構築 |
| `vm_service` | RPCエラーの分類 |
| `image` 4.9.1 | CLI側でのPNG検証 |
| `yaml` 3.1.4 | workflowのYAML解析 |
| `dart:io` / `dart:convert` / `dart:async` | socket、file lock、UTF-8、JSON、deadline、queue |

recordはVM Serviceに依存しない例外で、SessionManagerの共通session queueからRecordService→marionette_agent_utilへ委譲します。OS別の録画・終了シグナル処理はutilに集約し、refや接続世代は変更しません。

## コマンドの登録

通常コマンドは、同じ名前をCLIとdaemonの両方へ登録します。

1. `CliParser`の定義へ`CliCommand(ArgParser, decode)`を追加します。
2. `coreCommands()`へ`register(name, handler)`を追加します。
3. 製品entrypointが使用するparserとregistryの両方に登録されていることを確認します。

`decode`は`ArgResults`を文字列keyのJSON objectへ変換します。CLIを経由せずIPC paramsが届く場合があるため、handlerも許可field、型、必須条件、排他条件をすべて再検証します。未知fieldを無視してはいけません。

共通オプションの`--session`、`--json`、`--timeout`、`--content-boundaries`、`--max-output`、`--idle-timeout`、`--help`、`--version`は`cli/common_options.dart`に定義し、root parserがコマンドの前後で処理します。コマンドparserでは再定義しません。selectorを持つコマンドは`addSelectorOptions`を使い、CLI側では`parseTarget`、handler側では共有された`decodeTarget`相当の検証を使います。

登録と1回送信の最小例は次のとおりです。

```dart
final parser = CliParser(
  commands: {
    'verify-tap': CliCommand(ArgParser(), (args) {
      if (args.rest.length != 1) invalid('Usage: verify-tap <ref>');
      return {'ref': RefQuery(args.rest.single).ref};
    }),
  },
);

final commands = coreCommands()
  ..register('verify-tap', (context, params) {
    if (params.length != 1 || params['ref'] is! String) invalid();
    return context.performTarget(
      RefQuery(params['ref'] as String),
      (backend, selector) => backend.tap(ElementTarget(selector)),
    );
  });
```

実行可能な例は[probe_cli.dart](../../packages/marionette_agent/integration_test/support/probe_cli.dart)にあります。

## 引数検証

引数の構築と検証は、`CommandContext`のmutation経路へ入る前に完了させます。mutation開始後の引数エラーはrefをすでに失効させ、操作送信後の失敗として分類される可能性があります。

要素対象は次のどちらか正確に1つです。

- `RefQuery`: `@e1`形式のref。
- `SelectorQuery`: `key`、`identifier`、`text`、`type`のうち1属性による完全一致。

ref、selector、座標を混在させてはいけません。selector値は空文字を拒否します。数値文字列とJSON数値は`finiteNumber`で有限の`double`へ変換します。

| 型 | 不変条件 |
| --- | --- |
| `Point` | x、yが有限かつ0以上 |
| `ElementSwipe.distance` | 有限かつ0より大きい。既定200 logical pixel |
| `CoordinateSwipe` | 始点と終点が異なる |
| `Direction` | `left`、`right`、`up`、`down`。コンテンツではなく指の移動方向 |
| `WaitRequest.pollIntervalMs` | 50〜1,000の整数。既定100ms |

## CommandContext

`CommandContext`はコマンドhandlerがsession内部状態へ触れるための唯一の経路です。

| API | 現在の動作 |
| --- | --- |
| `snapshot()` | backendを観測し、公開snapshotを置き換えて新しいrefを発行する |
| `observeTarget(query)` | 共通の再観測・一意性・stale判定で1要素を返す。非表示も受理し、refを維持する |
| `performTarget(query, callback)` | 対象を再観測して一意性と属性を検証し、全refを失効させてからcallbackを1回実行する |
| `performCoordinates(callback)` | 全refを失効させてから、座標操作のcallbackを1回実行する |
| `read(callback)` | refを維持したread-only処理。`await`の前後で接続世代とdeadlineを検証する |
| `check()` | workflowの親停止状態を含め、現在の処理が結果を公開できるか確認する |
| `deadline` | CLI受付時から共有される絶対deadline |
| `session` | 対象session名。接続URIは公開しない |

1つの`Execution`が送信できるUI mutationは最大1回です。`performTarget`と`performCoordinates`へ渡すcallbackも、backend primitiveを正確に1回だけ呼びます。handlerは独自のretry、session作成、queue、ref保存、接続破棄を実装しません。

UI操作の成功はbackend呼び出しが完了したことだけを表します。通常のmutation結果は`{"requiresSnapshot":true}`です。画面が期待どおり変化したかは、後続の`snapshot`で確認します。

## session、deadline、送信結果

`SessionManager`は同じsessionの要求を1本のqueueで直列実行し、異なるsessionは並行実行できます。queue待ちも要求のdeadlineに含まれます。期限切れのqueue要求は後から実行しません。

`Execution.bound`は、操作をbackendへ送ったかどうかを`sent`で保持し、エラーの`outcome`を次のように決定します。

| 状況 | outcome | session / ref |
| --- | --- | --- |
| 引数不正、未接続、対象不一致、queue内で期限切れ | `not_sent` | mutation未送信。送信前ならrefを維持 |
| backendがmutation失敗を確定 | `failed` | 接続を維持し、refは失効済み |
| mutation送信後のtimeout、切断、未分類エラー | `unknown` | 接続世代を破棄し、refを失効 |
| read中のtimeoutまたは切断 | `not_sent` | 接続世代を破棄し、refを失効 |

timeoutした`Future`自体は停止できないため、すべてのreadとmutationは接続世代を再確認します。古い処理の遅延完了は、再接続後のsession状態やsnapshotを変更できません。送信後に結果が不明な操作を自動再送してはいけません。

## snapshotと対象解決

`SnapshotService`はdaemon単位でsnapshot generationとref番号を単調増加させます。新しい公開snapshotを取得すると、そのsessionの以前のrefはすべて失効します。ref番号はsession間でも再利用しません。

公開snapshotは、取得できた`type`、`text`、`key`、`identifier`、`bounds`、`visible`だけを返します。非表示要素には`reason: "not_visible"`を付けます。表示中でも一意で安全なselectorを作れない要素には`reason: "no_unique_supported_selector"`を付け、refを発行しません。

固定binding 0.6.0が操作に使えるselectorは`key`、`text`、`type`です。`identifier`は観測結果に存在しても操作には未対応で、`UNSUPPORTED_CAPABILITY`になります。textを安全に操作へ使えるのは、現在のadapterがmatcherとの対応を確認している`Text`、`RichText`、`EditableText`、`TextField`、`TextFormField`だけです。

refまたは明示selectorによるmutationの直前には、backendを再観測します。

- 0件: refなら`STALE_REF`、明示selectorなら`TARGET_NOT_FOUND`。
- 2件以上: `AMBIGUOUS_TARGET`。非表示要素や、text由来を確認できない要素も衝突数に含めます。
- refの保存属性から変更: `STALE_REF`。
- 一意でも非表示、またはtext matcherとの対応を確認できない: `UNRESOLVABLE_TARGET`。

再観測とbackend操作は原子的ではなく、観測結果も完全なWidget treeではありません。未観測要素や再観測後の画面変化は保証対象外です。refから座標へのfallbackは行いません。

## Backend adapter

`Backend`は次の型付きprimitiveを公開します。

```text
connect / disconnect / checkConnection / inspect
tap / fill / swipe / captureScreenshots / readLogs
```

`MarionetteBackend`はVM Service URIを正規化し、HTTP(S)をWS(S)へ変換して末尾を`/ws`にします。pathとqueryは接続に保持しますが、状態表示ではhostとport以外を秘匿します。上流responseは`status == "Success"`と構造を検証し、生のmessage、例外、入力文字列を上位層へ転送しません。

`scroll`は独立したbackend primitiveではなく、要素指定の`swipe`を使用します。成功結果には通常の`requiresSnapshot`に加えて`"command":"scroll"`を含めます。

## is visible

`is visible`は`observeTarget`で得たnullableなvisibleを`known`と`value`へ変換します。true/falseはいずれも既知、nullは`known:false,value:null`です。公開snapshotを作らず、UI mutationを送らず、成功時は同じrefを再利用できます。対象解決エラーは通常の共通契約に従います。

## wait

単独waitとworkflow waitは`commands/wait.dart`の同じ`handleWait`へ、selector、state、poll間隔を正規化して渡します。単独waitは共通`--timeout`、workflow waitはstep期限とworkflow全体期限の早い方をExecutionのdeadlineとして使います。

handlerは全paramsとselector capabilityを観測前に検証し、`CommandContext.read`で`Backend.inspect`だけを直列pollします。`exists`は一意性、visibility、text由来を検査し、`gone`は0件だけを成功とします。mutation経路を使わないため送信回数は0で、成功時は既存refを維持します。read中のtimeout／通信断は既存契約どおり`not_sent`で接続世代を破棄し、queue開始前のtimeoutは観測せず接続を維持します。

## screenshotとlogs

`screenshot`と`logs`はread-onlyであり、既存refを失効させません。

screenshot画像はbase64 PNGとしてdaemonからCLIへ返り、CLIがdecodeとPNG検証を行います。保存時の契約は次のとおりです。

- 公開結果には絶対pathの`paths`だけを返します。
- 出力先省略時はsystem temp配下の専用directoryへ`screen.png`として保存します。
- 1画像では指定pathをそのまま使います。複数画像は`name-1.png`、`name-2.png`のように連番化し、指定pathに拡張子がなければ連番pathへ`.png`を付けます。
- 親directoryは事前に存在する必要があります。
- 既存のfile、directory、symlinkを上書きしません。
- 同じ親directoryのmode 0700 stagingへ書き、POSIX hard linkで排他的に公開します。macOSとLinux以外、またはhard link非対応のfile systemでは`IO_ERROR`です。
- batch公開の途中で競合した場合、すでに公開済みの画像は安全のためpath指定で削除せず、error hintで部分保存を通知します。
- decode、検証、保存の全体で元のrequest deadlineを使用します。

logsは`entries`、nullableな`configured`、必要に応じて`limitation`を返します。bindingがログ未設定を明示した場合は`configured:false`です。未設定と空配列を区別できないbackendでは`configured:null`と制約説明を返します。bindingから取得したログはstdoutの結果dataであり、診断ログとは別です。

## 結果、エラー、診断

公開結果は成功・失敗とも`Result`の1つのJSON envelopeです。

```json
{"schemaVersion":1,"ok":true,"session":"demo","data":{},"error":null}
```

`AgentError`は`code`、安全な`message`、任意の`hint`と`details`、`outcome`を保持します。主な終了コードは次のとおりです。

| 終了コード | code |
| --- | --- |
| 2 | `INVALID_ARGUMENT` |
| 3 | `NOT_CONNECTED`、`SESSION_CONFLICT`、`CONNECTION_LOST` |
| 4 | `TARGET_NOT_FOUND`、`AMBIGUOUS_TARGET`、`STALE_REF`、`UNRESOLVABLE_TARGET` |
| 5 | `TIMEOUT` |
| 6 | `UNSUPPORTED_CAPABILITY` |
| 1 | `BACKEND_ERROR`、`IO_ERROR`、`INTERNAL_ERROR`など |

INFO以上のdiagnostic recordだけをstderrへ出します。認証情報を含むURIは`<redacted-uri>`へ置換し、改行をescapeします。上流のerror objectとstack traceは転送しません。INFO未満には入力文字列が含まれる可能性があるため収集しません。コマンド実装も、認証URIや`fill`入力をdiagnostic、error message、call履歴へ含めてはいけません。

## workflowからの再利用

workflowは`SessionManager`で通常の1コマンド経路から分岐し、1つのqueue entryを完了まで占有します。各stepには新しい`Execution`と`CommandContext`を作り、1 step 1 mutationの制約を維持します。stepから`SessionManager.handle`を再帰呼び出ししてはいけません。

workflowが通常handlerを利用できるactionは`snapshot`、`tap`、`fill`、`swipe`、`scroll`、`wait`です。waitは単独コマンドと同じread-only handlerを利用し、step固有期限だけをworkflow側で設定します。stepで確定したoutcomeは親workflowで変更せず、進捗detailsを追加します。詳細は[workflow v1仕様](workflow-file-spec.ja.md)を参照してください。

## 検証

コード変更後は`packages/marionette_agent`で次を実行します。

```sh
dart format .
dart analyze
dart test
```

主な契約テストは次のとおりです。

- [feature_commands_test.dart](../../packages/marionette_agent/test/feature_commands_test.dart): tap、fill、scroll、screenshot、logs。
- [swipe_test.dart](../../packages/marionette_agent/test/swipe_test.dart): 2種類のswipeと送信結果。
- [snapshot_test.dart](../../packages/marionette_agent/test/snapshot_test.dart): ref、属性再検証、重複、text matcher。
- [session_test.dart](../../packages/marionette_agent/test/session_test.dart): session所有権、queue、timeout、再接続。
- [transport_test.dart](../../packages/marionette_agent/test/transport_test.dart): IPC切断、version、64 MiB上限。
- [artifact_writer_test.dart](../../packages/marionette_agent/test/artifact_writer_test.dart): PNG検証と排他的保存。
- [workflow_execution_test.dart](../../packages/marionette_agent/test/workflow_execution_test.dart): workflowのstep境界と遅延応答。
- [wait_test.dart](../../packages/marionette_agent/test/wait_test.dart): 単独／workflow waitの条件判定、入力、期限、queue、ref、送信0回。

CLI機能を追加・変更した場合は、unit testだけでなく`example`をiOS Simulatorで起動し、製品CLI経由の画面変化まで確認します。
