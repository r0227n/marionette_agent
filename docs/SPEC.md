# marionette_agent — 製品仕様

## 環境診断 doctor (Issue #9)

`doctor [--probe-uri <uri>]` は接続不要のローカル診断。sessionはnull。
通常実行はruntime作成・permission変更・socket削除・daemon起動/停止・package導入・Simulator起動を行わない。追加の`--quick/--offline/--fix`は後述のFlutter向け拡張に従う。
既存session/backend/refへ要求を配送せず、daemonではhandshakeだけを読み接続を破棄する。
handshakeだけの照会ではdaemonの既存idle期限を更新しない。

成功した診断実行のenvelopeは`ok:true`、dataは`doctor:true`、`exitCode`、`checks`。
各checkは`id`、`status`、`reason`、利用者が実行する`nextStep`、`details`を持つ。
statusは`success`(条件確認済み)、`failure`(不適合を確認)、`unknown`(timeout/観測失敗)、
`skipped`(対象不在/明示probeなし/前提不成立)。failureまたはunknownが1件でもあれば終了1、
それ以外は終了0。これは診断コマンド固有の集計であり、引数エラー等は通常のerror契約を使う。
`--timeout`は全checkを含む全体期限。期限切れcheckと残りはunknownとして終了1。

check IDと対象:
- `host.os`: macOS。`host.dart`: 実行SDKが>=3.13.2 <4.0.0。
- `runtime.socketPath`: 既存runtimeと同じ絶対path/80 UTF-8 bytes上限、socket `/s` のbyte数。
- `runtime.directory`: symlink不可、現在user所有、0700。不存在はskippedで作成しない。
- `daemon.ipc`: 安全確認済みdirectoryのsocketに受動接続、protocolVersion一致とreadyを確認。
  不在はskipped、拒否/不一致はfailure、無応答はunknown。最大1秒か残り期限の短い方。
- `dependencies.fixed`: CLI packageのpubspec/lockのmarionette_mcp、image、yaml固定version比較。
  ファイル不在/取得不可はunknown。実bindingやインストール済み実体のversion保証ではない。
- `simulators.ios`: `xcrun simctl list devices available --json`でiOS端末の名前/UDID/runtime/stateを観測。
  0台はfailure、照会失敗はunknown。起動/修復はしない。
- `probe.vmService`: `--probe-uri`指定時だけ独立したVM clientを作成し、getVersion/getVM/getIsolateと
  登録済み`ext.flutter.marionette.getVersion`だけを照会。未指定はskipped、接続/RPC異常はfailure、
  timeoutはunknown。binding versionは有効な応答がある時だけ、capabilityは実際に登録されたextension名のみ。
  未観測versionはnull/unknown、未観測bindingはunknown。登録確認は操作成功の保証ではない。

probeの認証URI・remote exception・入力文字列は結果/診断へ出力しない。probe終了/失敗/期限切れでは
独立接続を解放し、遅れて成立した接続も閉じる。外部照会processは期限切れで終了させる。
実macOS/Simulator受入検証は[Issue #9記録](../packages/marionette_agent/docs/verification/issue-9.md)を参照。

状態: `marionette_agent 0.0.1` の実装済み契約。単独コマンドとworkflow v1を含む。利用方法の詳細は[日本語CLIリファレンス](ja/cli-reference.ja.md)、内部の実装境界は[アーキテクチャ](ARCHITECTURE.md)を参照する。

## 目的と対象

Dart製CLIから、Marionette対応FlutterアプリをAI Agentが観測・操作できるようにする。agent-browserのsession、snapshot、短い要素参照、構造化出力という操作体系を採用する。ブラウザー固有のコマンド互換性は目的に含めない。

初版の実行ホストはmacOS、主なUI操作対象はiOS Simulator内の起動済みFlutterアプリ。recordは別途iOS Simulator／Android／macOSディスプレイ（ChromeのWeb検証を含む）を対象とする。アプリはdebug実行され、`marionette_flutter` のbindingが初期化済みで、接続可能なVM Service URIが必要。Simulatorやアプリの起動・ビルド・インストールは利用者側で行う。

MCPサーバー／クライアントの提供は対象外。`marionette_mcp` のDart接続実装をライブラリーとして利用し、VM Service経由でFlutter拡張を呼び出す。

## 用語

| 用語 | 意味 |
| --- | --- |
| session | 名前で選ぶ、1つのFlutterアプリへの接続と観測状態の単位 |
| daemon | sessionの接続と参照をコマンド間で保持するローカル常駐プロセス |
| snapshot | Marionetteから取得した操作可能要素・可読情報の観測結果。完全なWidgetツリーではない |
| ref | snapshot内の要素を指定する `@e1` 形式の短い参照 |
| selector | key・identifier・text・typeのいずれかによる明示的な対象指定 |

## CLI契約

実行名は `marionette-agent`。Dartパッケージ名は `marionette_agent`。`pubspec.yaml` のexecutableとして登録する。

```sh
marionette-agent --session demo connect 'ws://127.0.0.1:12345/token/ws'
marionette-agent --session demo snapshot
marionette-agent --session demo tap @e1
marionette-agent --session demo snapshot
marionette-agent --session demo fill @e5 'hello'
marionette-agent --session demo snapshot
marionette-agent --session demo swipe @e9 left --distance 200
marionette-agent --session demo screenshot ./screen.png
marionette-agent --session demo close
```

refは例示。実行時には直近snapshotに返されたものを使う。

### 共通オプション

| オプション | 契約 |
| --- | --- |
| `--session <name>` | 省略時は `MARIONETTE_AGENT_SESSION`、未設定なら `default`。英数字で始まる英数字・`_`・`-`、最大64文字 |
| `--json` | stdoutへ1つのJSONオブジェクトを出力 |
| `--timeout <ms>` | DurationとDateTimeで表現可能な正の整数。省略時は `MARIONETTE_AGENT_TIMEOUT_MS`、未設定なら30,000ms。待ち行列・接続・処理を含む期限。範囲外はINVALID_ARGUMENT |
| `--debug` | 値なしflag、既定無効。request ID・session・処理段階・経過ms・終了時の正規化error codeをstderrへ出力 |
| `--content-boundaries` | 値なしflag、既定無効。snapshot要素／logs entryを未信頼コンテンツとして識別 |
| `--max-output <chars>` | 正の整数、既定無制限。snapshot／logsの項目列をUnicode code point数で制限 |
| `--idle-timeout <duration>` | daemon全体のidle期限。既定1h、0で無効。整数msまたはms/s/m/h接尾辞 |
| `--screenshot-format png\|jpeg` | screenshotの保存形式。既定png。backendはPNGのまま、CLI側でJPEGへ変換 |
| `--screenshot-quality <0-100>` | JPEG指定時だけ受理する整数。省略時90。PNG指定時・単独指定・範囲外はINVALID_ARGUMENT |
| `--screenshot-dir <path>` | path省略のscreenshotを保存する既存directory。既定未指定。明示pathを優先し、両方省略時は従来の一時保存 |
| `--help` / `--version` | 接続なしで利用可能 |

共通オプションはサブコマンドの前後で受け付ける。同じオプションの重複は引数エラー。通常は対話入力を要求せず、明示した`--confirm-interactive`だけがTTYで確認する。通常出力は簡潔なテキスト、診断ログはstderr。引数不足は非ゼロで終了し、使用可能な構文を示す。

sessionとtimeoutはそれぞれ明示CLI > 環境変数 > 明示config > 既定値の順で選び、選択された値だけに既存の名前・正整数・Duration／DateTime範囲検証を適用する。環境変数の空文字も設定済みとして扱い、不正ならINVALID_ARGUMENTとする。明示CLIで上書きされた環境値は空文字・不正値でも検証しない。明示CLIの欠損・重複・不正値は環境値へ戻さず引数エラーとする。環境変数はCLI呼出しごとに解決し、選択したtimeoutはqueue待ちを含む既存の絶対deadlineへ変換する。configは明示`--config`で提供する。認証情報、session id、idle-timeoutの環境fallbackは提供しない。

構文エラーでも、有効に選択されたsession（環境値を含む）とJSONモードを応答へ反映する。不正なsessionはnull、session非依存コマンドもnullとする。オプションの値や`--`以降にある文字列を共通オプションとして解釈しない。

`--debug`は構文エラーを含めopt-inで診断を追加し、通常診断とstdoutの既存envelopeは維持する。CLIからdaemonへ要求単位で伝え、並行sessionで設定・診断を共有しない。処理段階はCLI解析、runtime準備、daemon接続・起動・ready、送信、dispatch、session queue、command実行、結果。各プロセス内の処理区間開始からの単調な経過時間をmsで表示し、結果には成功の`OK`または正規化error codeを付ける。認証URI、fill入力、selector値、アプリ表示text、error message/details、stack traceは詳細診断に含めない。

### 共通安全オプション

共通オプションの登録・CLI既定値・優先順位・構文エラーの出力モード回復は`cli/common_options.dart`を正本とし、全サブコマンドはrootの同じ定義を継承する。session名・期限・出力上限の値域検証とdaemon idle既定値は`protocol/protocol.dart`に定義し、CLIとIPCで共用する。`--debug`を含む共通オプションはhelp/version、workflow、recordで受理する。重複・欠損・不正値はINVALID_ARGUMENT。環境変数のfallbackはsessionとtimeoutだけに適用し、明示設定ファイルの値を環境変数より下位の既定値として使う。screenshot形式・品質は画像保存時だけ使用し、他コマンドの出力は変更しない。

`--content-boundaries`はsnapshotの要素行とlogsのentryだけを`--- BEGIN UNTRUSTED <source> <nonce> ---`／`--- END UNTRUSTED <source> <nonce> ---`で囲む。sourceは`snapshot`または`logs`、nonceはCLI呼出しごとにRandom.secureから生成する128bitの小文字hex。見出し、件数、エラー、hint、診断は外側に置く。JSONは文字列を変更せず、対象dataの`contentBoundary: {nonce, source}`へ同じ境界情報を格納する。内容の無害化や命令判定ではない。

`--max-output`は公開観測・generation・全要素のref採番を確定してから、elements／entriesの先頭から収まる完全な項目だけを返す。textはsnapshot要素行またはJSON化したlog entry、JSONは各項目のcompact JSONをcode pointで数える。項目間の改行／commaは各1文字として含め、包絡、配列括弧、見出し、境界、件数metadataは含めない。最初の項目が収まらなければ空配列。設定時は同じdataに`truncated`（bool）、`originalCount`、`omittedCount`を常に追加する。省略したrefはsessionから削除し、番号の推測利用はSTALE_REF。次回snapshotでも採番を巻き戻さない。workflowのfinalSnapshotも同じ契約。画像base64、保存画像、stderr診断、IPCの64MiB上限には適用しない。

idle timeoutは起動時に確定しdaemonの寿命中は変更しない。`10s`、`3m`、`1h`、`10000`（ms）、`10ms`を受理し、負数・小数・未知単位・Duration／DateTime範囲外はINVALID_ARGUMENT。省略した呼出しは稼働値を引き継ぐ。異なる値を明示したIPC呼出しはhandshakeで処理送信前にINVALID_ARGUMENT／not_sentとなる。同時起動も起動lockの取得後に再照合し、最初に確定した設定だけを使う。help/version、workflow schema/validateはローカルで完了しdaemonへ接触しない。

全session queueと要求の配送がidleになってから計測し、実行中・queue待ち中の処理は中断しない。health probeは終了を妨げない範囲で待ち、利用者の無操作時間を更新しない。期限到達時は通常のshutdownで録画を確定し、全接続・refを破棄してsocket・寿命lockを解放する。録画だけが継続していても要求queueがidleなら終了対象。次のアプリ操作はNOT_CONNECTEDとなり、明示的なconnectと新snapshotが必要。Flutterアプリ自体は終了しない。

### 実装済みコマンド

| コマンド | 動作 |
| --- | --- |
| `connect <uri>` | 指定sessionで接続。HTTP(S)のVM Service URIもWS(S)へ正規化 |
| `skills [list]` / `skills get <name> [name...] [--full]` / `skills get --all [--full]` / `skills path [name]` | 同梱Skillの一覧・本文・既存pathをローカルで返す |
| `session list` | sessionの名前・接続状態を一覧表示。daemon不在時は空一覧 |
| `session show` | 選択sessionの状態、秘匿済み接続先、snapshotの有効性を返す |
| `close [--all]` | 録画があれば確定し、選択session（--allは全session）を切断・破棄。対象不在も成功。Flutterアプリは終了しない |
| `snapshot` | 観測を更新し、要素一覧とrefを返す |
| `get text <ref\|selector>` | 単一要素の観測textを返す |
| `get box <ref\|selector>` | 単一要素のboundsをFlutter論理座標で返す |
| `get count <selector>` | 完全一致する観測候補の件数を返す（ref不可） |
| `is visible <ref\|selector>` | 可視状態をknown/valueで返す。未観測はunknown |
| `tap <ref>` / `tap <selector>` | 対象を1回タップ |
| `tap --x <n> --y <n>` | 明示座標を1回タップ |
| `fill <ref> <text>` / `fill <selector> <text>` | 入力欄の内容を置換。空文字でクリア |
| `swipe <ref> <direction> [--distance <n>]` | 要素を起点にスワイプ。selectorも使用可能 |
| `swipe --start-x <n> --start-y <n> --end-x <n> --end-y <n>` | 明示した始点から終点へスワイプ |
| `scroll <ref> <direction> [--distance <n>]` | スクロール領域への方向付きジェスチャー。selectorも使用可能 |
| `wait <selector> [--state exists\|gone] [--poll-interval <ms>]` | 要素の出現または消失を観測だけで待つ |
| `screenshot [--annotate] [path]` | PNG（既定）またはJPEGを排他的に保存。明示path > `--screenshot-dir` > 一時ファイル。注釈は対応providerと直近の有効snapshotが必要 |
| `logs` | bindingで収集されたログを取得。購読や無期限の待機はしない |
| `record start <path> --platform <platform> --device <id>` | 端末画面録画を開始。VM Service接続は不要 |
| `record status` / `record stop` | 録画状態を照会／動画確定まで待って停止 |
| `workflow schema [action]` | workflow全体またはaction別の同梱JSON Schemaを返す。daemon・接続は不要 |
| `workflow validate <path>` | JSON／YAML workflowを読んで構文・schema・意味制約を検証。daemon・接続は不要 |
| `workflow run <path>` | 接続済みsessionでworkflowを1要求として直列実行 |

`<selector>` は `--key <value>`、`--identifier <value>`、`--text <value>`、`--type <value>` のいずれか1つ。例: `fill --key email 'a@example.com'`、`swipe --key pager left`。ref、selector、座標の混在はエラー。`wait`はselectorだけを受理し、refと座標を受理しない。固定依存のbinding 0.6.0はidentifier matcherを提供しないため、identifier指定はUNSUPPORTED_CAPABILITYを返す。

scrollは初版では指定領域を既存swipe機構で操作する。directionはswipeと同じく指の移動方向であり、コンテンツの移動先や到達保証ではない。画面外要素へのscroll-toは後続とする。

単独`wait`の`state`は`exists`が既定で、`gone`も指定できる。`poll-interval`は50〜1,000msの整数、既定100ms。最初の観測は即時に行い、全体期限は共通`--timeout`を使う。`exists`は一致が正確に1件かつ`visible != false`で成功し、複数一致はAMBIGUOUS_TARGET。`gone`は0件で成功し、1件以上なら待つ。text照合では由来未確認の候補も衝突へ含め、唯一の候補が由来未確認ならUNRESOLVABLE_TARGETとする。

`wait`は同一session queueで`inspect`だけをpollし、UI操作を送信せず、公開snapshot／refを発行・更新・失効しない。成功dataは待機した`state`と`requiresSnapshot:true`を返し、実際の画面状態と最新refを後続`snapshot`で確認するよう案内する。wait中のtimeoutまたは通信断はreadの既存契約どおり`outcome:not_sent`で接続世代とrefを破棄する。queue内で実行開始前に期限切れとなった要求は観測せず、接続とrefを維持する。

### screenshotの形式・保存

- 注釈なしの既定PNGは復号検証後にbackendの元バイト列を保存し、寸法と透過を保持する。JPEGはCLI側でPNGを復号し、各画素のRGBを白背景へalpha合成してから不可逆圧縮する。寸法は変えない。PNG内の背景色指定は使用しない。
- `--screenshot-format`は小文字の`png`または`jpeg`。`--screenshot-quality`はJPEG指定時だけ0〜100の整数を受理し、既定90。固定encoderの品質0は最低品質1と同じ圧縮になる。品質100もlosslessではない。
- pathの拡張子はPNGなら`.png`、JPEGなら`.jpg`または`.jpeg`。大文字小文字を区別せず、指定した綴りは維持する。形式は拡張子から推測しない。不一致・未知の拡張子は接続前にINVALID_ARGUMENT。拡張子がなければPNGは`.png`、JPEGは`.jpg`を付加する。
- pathと`--screenshot-dir`を両方省略時は専用の非公開一時directoryに`screen.png`または`screen.jpg`を保存する。複数画像はbackendの順で、指定名の拡張子直前へ`-1`、`-2`…を付ける。例: `screen.jpeg`→`screen-1.jpeg`、`screen-2.jpeg`。自動名も同じ連番規則。
- 共通`--timeout`は取得・転送・復号・白背景合成・JPEG変換・保存を含む元の絶対期限。codec処理前後・合成中・保存中に期限を確認し、期限後に成功を返さない。同期codecや進行中のOS I/Oの即時中断は保証しない。
- 全画像の復号・変換が成功してから全保存先を排他的に予約し、書き込む。既存file/directory/symlinkはIO_ERRORで拒否する。途中の変換失敗は出力を作らず、予約・書込みの失敗やTIMEOUTではこの要求が作成した全fileと自動作成directoryの削除を試みる。既存fileを削除・上書きしない。OSがcleanupを拒否した場合は部分artifactが残る場合があり、成功pathsは返さない。意図的な予約後の差し替えは従来どおり保証外。

### workflow v1

workflow v1はJSONまたは制限付きYAMLで`snapshot`、`tap`、`fill`、`swipe`、`scroll`、`wait`を記述順に実行する。`run`は全stepを同一sessionの1つのqueue entryで実行し、最初の失敗で停止する。完了済みstepのrollback、自動retry、途中再開は行わない。

workflow内の操作対象はselectorだけを受理し、refと座標操作は受理しない。入力値は型付き参照でbindingし、文字列展開、環境変数展開、shell実行は行わない。`--timeout`はworkflow／inputsの読込、検証、daemonへの配送、queue待ち、全stepを含む絶対期限である。

成功時はworkflow名、完了step数、`requiresSnapshot`を返す。workflow内で最後に取得され、その後mutationされていないsnapshotがあれば`finalSnapshot`として返し、そのrefを後続CLIから利用できる。失敗時は`error.details`へ進捗の既知・未知、完了step数、失敗stepを付加する。詳細なfile schema、上限、waitの意味は[workflow v1仕様](ja/workflow-file-spec.ja.md)を正本とする。

### sessionの寿命と競合

- connectまたはrecord startでdaemonを必要に応じて自動起動する。アプリ操作コマンドが未接続sessionを暗黙作成することはない。
- 同一session・同一URIへのconnectは、接続が正常なら成功。別URIへの付け替えにはcloseを先に実行する。
- sessionごとにコマンドを直列実行する。異なるsessionは独立する。同じ正規化URIを複数sessionで所有する要求は拒否する。URI別名による同一アプリの検出は保証しない。
- 通信断でsessionはdisconnectedとなりrefを失効する。明示的なconnectで復旧する。操作の自動再送はしない。
- daemon再起動で接続・snapshotを復元しない。最後のsessionを閉じたdaemonは終了する。
- タイムアウトしても送信済み操作を取り消せたとは限らない。結果不明を返し、接続を破棄して再接続と再観測を要求する。

### getによる状態照会

`get text`と`get box`は対象を再観測し、操作と共通の一意性・ref属性比較を使用する。selectorが0件ならTARGET_NOT_FOUND、複数件ならAMBIGUOUS_TARGET、未発行／消失／属性変更したrefならSTALE_REF。単独の由来未確認text selectorはUNRESOLVABLE_TARGET。表示不可でも観測された属性は返せるため、操作専用のvisible判定は行わない。

成功dataはtextが`{"text":string|null}`、boxが`{"bounds":{"x":number,"y":number,"width":number,"height":number}|null,"unit":"flutter_logical_pixels"}`。boundsはFlutter論理座標であり、Simulator画像の物理pixelではない。欠損はnull、実際の空文字やゼロはそのまま返す。入力欄のvalue属性を取得する契約ではない。

`get count`の成功dataは`{"count":integer,"selector":{kind:value}}`。現在のinspect結果についてkey/identifier/text/typeの完全一致を数え、0件・複数件とも成功する。textはcandidateValueを使い、既知型と由来未確認型の観測textをそれぞれ1候補として数える。これは上流操作matcherの実一致数や操作可能性の保証ではない。refはINVALID_ARGUMENT、binding未対応selectorは件数にかかわらずUNSUPPORTED_CAPABILITY。成功した全getは公開snapshotの世代・refを更新／失効／再発行しない。timeout・通信断は既存read契約に従う。

### is visible

`is visible <ref|selector>`は一度だけ対象を再観測する読み取りコマンド。成功のJSON `data`は`{"known":true,"value":true}`、`{"known":true,"value":false}`、`{"known":false,"value":null}`のいずれかとする。nullableなvisibleの未観測をfalseへ丸めない。textはそれぞれ`Visible: true`、`Visible: false`、`Visible: unknown`。

共通の対象再観測・一意性・属性比較を利用する。selectorの0件は`TARGET_NOT_FOUND`、複数件は`AMBIGUOUS_TARGET`、古いrefは`STALE_REF`、未対応selectorは`UNSUPPORTED_CAPABILITY`。非表示の一意な対象は成功してfalseを返す。成功時はUI操作、refの失効・再発行、公開snapshot世代の更新を行わない。待機やenabled/checkedの判定は含まない。


### close --all

`close --all`はdaemon全体の後始末。明示的な`--session`との併用（defaultも含む）はINVALID_ARGUMENT（exit 2）。daemon不在・空でも成功し、自動起動しない。成功はsession:null、data:{closed:true,sessions:[session別Result]}。名前順の各Resultは通常の包絡（session、ok、dataまたはerror）を使う。closedはローカルsessionの破棄を表し、アプリ終了を意味しない。

受付時に対象sessionを固定して全新規要求の受付を停止する。それ以前に予約したconnectも対象に含む。queue待ちは実行前にCONNECTION_LOST/not_sentとして拒否し、実行中は共通`--timeout`の絶対期限まで完了を待つ。期限到達で接続世代を失効し、送信済み操作の応答はCONNECTION_LOST/unknown、未送信はnot_sent。遅延完了によるref復活・後続操作の送信・UI再送を禁止する。

sessionごとに録画確定・切断を期限内で待つ。部分失敗でも全sessionのref・URI所有権を破棄しdaemonを終了する。部分失敗はdata:null、error.details:{closed:true,sessions:[session別Result]}。期限超過が1件でもあればTIMEOUT（exit 5）、それ以外の失敗はCLOSE_FAILED（exit 1）。集約outcomeは結果不明があればunknown、それ以外はfailed。各sessionに切断成功、失敗、期限超過を残す。IPC配送自体が途絶えた場合はunknownとなり、session別結果を推測しない。

停止中daemonへ送信した新規connectはCONNECTION_LOST/not_sent。handshakeが停止中なら既存の起動lock／寿命lock経路で次daemonを待つことがあるため、close --allは将来の明示connectを禁止する障壁ではない。次回利用は明示connectと新snapshotが必要。socket削除と寿命lock解放は既存shutdown経路を使い、応答配送はdeadline+250ms、残client破棄はshutdown後250msに制限する。録画の期限後cleanupには既存のshutdown上限（60秒とabort猶予5秒）を適用する。

### snapshotと要素参照

snapshotは観測世代と要素一覧を返す。各要素には取得可能なtype、text、key、identifier、bounds、visibleを含める。存在しない属性は捏造しない。テキスト出力には対象選択に必要な情報を優先し、診断プロパティ全量を載せない。

`snapshot [--key <value> | --identifier <value> | --text <value> | --type <value>]`は省略可能なfilterを1つだけ受理する。値は空でない文字列で、観測属性との大文字小文字を区別した完全一致。複数selector、ref、未知option、空値はINVALID_ARGUMENTで観測前に拒否する。filterなしの出力は従来どおり。0件・複数件も成功した新snapshotであり、旧refはすべて失効する。

filterは観測用であり、`--text`は未知型を含む表示textにも一致する。`--identifier`もbackendの操作selector対応とは独立して観測済みidentifierに一致し、属性がなければ0件。表示textへの一致だけでは操作可能性を保証しない。操作には別途、対応確認済みselector・全観測結果での一意性・可視性の確認が必要となる。

処理順は全要素の観測→全体での一意性確認とref採番→filter→`--max-output`。filter外の衝突もref安全性に含め、番号は表示範囲で振り直さない。filter外・出力制限で省略されたrefは利用不可（STALE_REF）。filter時だけdataに`filter: {kind, value, matchedCount, totalCount}`を追加する。kindはkey/identifier/text/type、valueは指定文字列、totalCountは全観測要素数、matchedCountは出力制限前の一致数。text形式もFilter行に同じ条件・件数を返す。filter自体はtruncatedを意味しない。`--max-output`設定時のoriginalCountはfilter後の件数（matchedCount）、omittedCountはそのうち予算で省略した件数。filter metadataは文字数予算外。workflow v1のsnapshot step構文は変更しない。

refは選択sessionの直近snapshotだけで有効。新snapshot、再接続、切断で既存refを失効する。UI操作をバックエンドへ送る直前にも全refを失効し、成功・失敗・結果不明のいずれでも再snapshotを要求する。引数検証のみの失敗は失効させない。成功したwait、screenshot・logs・状態照会は失効させない。

ref番号はdaemonの生存期間を通して単調増加し、sessionをまたいでも再利用しない。daemon再起動後は必ずconnectとsnapshotからやり直す。

操作直前に再観測し、保存したselectorが一意に一致し、type・識別属性・text・boundsが観測時から変化していないことを確認する。不一致はSTALE_REF、複数一致はAMBIGUOUS_TARGET。refから座標への自動フォールバックは行わない。明示selectorでも観測内の一致数を確認する。

key、identifierを優先し、text・typeはバックエンドの照合との対応を確認できる場合に使う。表示用Semanticsテキストは照合用textと同義ではない。一意に操作できるselectorを構成できない要素は情報を表示するが、操作用refを付けず理由を返す。

固定binding 0.6.0ではtextの由来を区別する属性がないため、text照合は確認済みの型名Text・RichText・EditableText・TextField・TextFormFieldに限定する。Semanticsの派生型やその他の独自型のtextは表示情報として扱い、操作にはkeyまたは一意なtypeを使用する。

一意性の判定には由来未確認のtextも含める。同じtextを持つ未知の型が観測された場合、既知の型へのtext指定・text由来のref・wait existsもAMBIGUOUS_TARGETとして拒否する。snapshotは安全なkey/typeがあればそちらでrefを発行する。

既存APIでは再観測と操作は原子的ではなく、観測に含まれない要素もある。その間の画面変化や同一属性の別要素への置き換えを完全には検出できない。初版はこの制約下で事前検証を行い、Flutter要素の永続IDを保証しない。

### swipeの詳細

- 要素方式と座標方式の2方式。方向はleft・right・up・down。
- 距離は有限の正数、既定200。座標は有限の非負数。単位はFlutterの論理ピクセルであり、画像の物理ピクセルとは区別する。
- 座標方式は4座標をすべて必須とし、同一の始点・終点は拒否する。要素方式のオプションとの混在も拒否する。
- 速度・継続時間・慣性の指定、iOSホーム操作などのシステムジェスチャーは対象外。
- 成功はバックエンドのジェスチャー処理完了。ページ切替などの結果は次のsnapshotで確認する。

### 出力と終了コード

JSONは`skills`を除き成功・失敗とも以下の包絡形式。schemaVersionは初版で1。session非依存コマンドではsessionはnull。dataとerrorの一方だけを非nullとする。help/versionもJSONモードでは同じ包絡形式を使う。`skills --help`を含むSkill配信の互換出力は後述の専用契約に従う。

```json
{"schemaVersion":1,"ok":true,"session":"demo","data":{"requiresSnapshot":true},"error":null}
```

```json
{"schemaVersion":1,"ok":false,"session":"demo","data":null,"error":{"code":"STALE_REF","message":"Target changed","hint":"Run snapshot again","outcome":"not_sent"}}
```

outcomeはnot_sent・failed・unknown。送信後の通信断・タイムアウトを未実行として扱わない。

通常のテキスト出力でも全エラーにoutcomeを表示する。daemonが要求を処理した後、応答のサイズ超過等で結果を配送できなかった場合は、通常コマンドもunknownを返し、not_sentへ戻さない。

| 終了コード | エラー分類と代表code |
| --- | --- |
| 0 | 成功 |
| 2 | 引数: INVALID_ARGUMENT |
| 3 | 接続・session: NOT_CONNECTED、SESSION_CONFLICT、CONNECTION_LOST |
| 4 | 対象: TARGET_NOT_FOUND、AMBIGUOUS_TARGET、STALE_REF、UNRESOLVABLE_TARGET |
| 5 | 期限超過: TIMEOUT |
| 6 | 機能不足: UNSUPPORTED_CAPABILITY |
| 1 | その他: BACKEND_ERROR、IO_ERROR、INTERNAL_ERROR |

### screenshotの保存

screenshotのdataは絶対pathの`paths`配列。保存先は明示path、共通`--screenshot-dir <path>`、従来の非公開一時directoryの順に選ぶ。明示pathがあればdirectoryの存在や権限を調べず、その場所へ保存する。directory設定は呼出しごとで、daemon／sessionには保存せず、他コマンドの動作にも影響しない。空文字またはNULを含むdirectory指定はINVALID_ARGUMENT。

明示pathとdirectoryの相対pathは呼出元CLIのcwdを基準に正規化する。明示pathの親と指定directoryは事前作成を必須とし、自動作成しない。指定directoryの不存在、通常file、directory自身のsymlink（danglingを含む）、保存に必要な権限の不足はIO_ERROR。祖先directoryのsymlinkは解決を許す。directoryのtype確認後に意図的に差し替えられる競合までは保証しない。

directory指定時はその直下に`screen-<128bit乱数の32桁hex>.png`（JPEGは`.jpg`）を生成する。連続／同時撮影でも各要求で別名を生成し、排他的作成で上書きを防ぐ。万一生成名が既存pathと衝突した場合もIO_ERRORとして拒否する。両方省略時は従来どおり一意な`marionette-screenshot-*`一時directory内の`screen.png`または`screen.jpg`へ保存する。

複数画像は指定名／生成名の拡張子の前へ`-1`、`-2`の連番を付ける（拡張子なしは選択形式に応じて`.png`または`.jpg`を追加）。全PNGを復号検証し、全保存先を排他的に作成してから画像を書き込む。既存のfile・directory・symlinkは拒否する。途中失敗時はこの要求が作成した画像fileを削除し、一時保存の場合はこの要求の一時directoryも削除する。指定directoryと既存artifactは削除しない。cleanupの失敗で元のエラーを置き換えず、成功pathを返さない。保存先の予約後に別プロセスが意図的に差し替える競合までは保証しない。画像が空または不正PNGならBACKEND_ERROR、保存期限超過はTIMEOUT、その他の保存失敗はIO_ERROR。readであるscreenshotのこれらのエラーは従来どおりoutcome:not_sentとなる。

logsは返された範囲を正規化し、収集未設定と0件を識別できない場合、その制約を伝える。URIの認証部分や入力文字列を診断ログへ出力しない。

`screenshot --annotate`は、直近snapshotで実際に公開された操作可能refだけを`@eN`ラベルと枠として新しいPNGへ合成し、JPEG指定時は合成後にJPEGへ変換する。既存PNGを入力に取らず、元画像のbytesも変更しない。保存先は注釈画像の新規pathであり、通常のscreenshotと同じ排他的保存・全体deadlineを使う。成功dataはpathsに加えてannotated=true、generation、annotationCount、skippedAnnotationsを返す。refの採番・更新・失効は行わない。snapshotが無効、またはcapture前後の再観測で対象の一意性・属性が変わった場合はSTALE_REFとし、画像を保存しない。観測とcaptureは上流APIでは原子的でないため、途中で変化して元へ戻るアニメーションまで検出する保証はない。静止した画面で使用する。

固定`marionette_flutter: 0.6.0`の通常screenshot応答だけでは、画像とview、倍率、向きの対応を検証できない。注釈には別途opt-inの`marionette_agent.captureMappedScreenshot` providerが必要である。これは画像とgeometry v1を同時に返す限定契約であり、固定binding一般の注釈対応を意味しない。exampleのdebug構成はこのproviderを実装する。単一view、原点(0,0)、論理boundsに対する回転0、明示した論理幅・高さとPNG幅・高さだけを対応対象とする。portrait/landscapeは各時点の寸法を使い、画像を回転推測しない。未登録、複数view/画像、回転、寸法不一致などはUNSUPPORTED_CAPABILITYとし、注釈を保存しない。倍率をboundsや画像の外観から推測しない。

boundsが欠損・非有限ならmissing_or_invalid_bounds、幅/高さが非正または一部でもview外ならbounds_outside_viewとしてそのrefを省略し、skippedAnnotationsへ記録する。boundsを画面内へclampしない。ラベルは互いに重ならない位置へ配置し、移動したラベルは線で対象に結ぶ。配置領域不足はlabel_space_exhaustedとして省略する。操作可能refが0件でも有効snapshotとgeometryがあればannotationCount=0で保存できる。

## 検証基準

1. macOSからiOS Simulatorに接続し、別々のCLIプロセスでsnapshot→tap／fill／swipe→snapshotが成立する。
2. 2つのsessionの接続・ref・切断が分離され、同一sessionの並行要求が直列化される。
3. 古いref、曖昧な対象、通信断、timeoutが規定のJSONと終了コードになり、操作が自動再送されない。
4. PageViewの切替とDismissibleのdismissをswipeで確認し、座標方式もSimulatorで検証する。
5. wait、scroll、PNG/JPEG保存、ログ取得が共通のsession・deadline・エラー契約を通して動作する。
6. workflowのJSON／YAML検証、binding、queue占有、wait、停止時の進捗、最終snapshot引き継ぎを自動テストとSimulatorで確認する。
7. コード変更時は`packages/marionette_agent`でformat、analyze、関連testを実行する。CLI契約を変えた場合は`example/`をiOS Simulatorで起動し、製品CLIの結果と操作後の画面状態を確認する。

単体・IPC・契約テストは`packages/marionette_agent/test/`、Simulatorシナリオは`packages/marionette_agent/integration_test/`に置く。FakeBackendの成功だけをSimulator検証の代替にはしない。

## 同梱Skillの配信

`skills`はagent-browserの同梱Skill設計を採用するローカル読取コマンド。アプリ接続、runtime作成、daemon起動・照会、ダウンロード、Skillの生成やエージェント設定へのインストールを行わない。`--restore`やaction policyを実行せず、共通オプションの解析・値検証と`--debug`だけを共有する。batch/workflow/IPCの操作には追加しない。

- `skills`と`skills list`は名前順の一覧。textの説明は最大70 UTF-8 bytes付近の単語境界で省略し、JSONには全文を返す。
- `skills get <name> [name...]`は指定順でfrontmatterを含むSKILL.md全文を返す。`--full`は各Skillのreferences/、templates/直下の読めるテキストファイルを、ディレクトリ順・ファイル名順に追加する。再帰探索や実行はしない。
- `skills get --all`は非表示でない全Skillを名前順に取得。`--full`を併用可能。`--all`は名前指定より優先する。
- `skills path`は探索対象ディレクトリを1行ずつ、`skills path <name>`は名前に対応するSkillディレクトリを返す。ディレクトリ名ではなくfrontmatterのnameで検索する。
- `skills --help` / `-h`で専用help。`--json`はコマンドの前後で使用可能。共通契約の未知オプション・重複・余剰引数の検証を使用する。

`packages/marionette_agent/skills/marionette-agent/SKILL.md`は`hidden: true`の導入用stub。`skill-data/core/`と`skill-data/simulator-verify/`が実行時ガイドで、それぞれ補助reference/templateも同梱する。直下サブディレクトリのSKILL.mdからname・description・hiddenを簡易パースする。descriptionのインデント継続行は空白で連結、hiddenはtrue/yesを認識する。name欠損、frontmatter不正、読取不能なエントリは無視。hiddenはlist/--allから除外するが明示名でget/pathできる。空一覧は成功、get対象なしや未知名は失敗。重複nameは両方を一覧に残し、明示名では探索順の先頭を使う。

保存先の解決は、既存の`MARIONETTE_AGENT_SKILLS_DIR`（単独のSkill親ディレクトリ）を最優先する。不正・不存在のoverrideは通常探索へ戻す。通常は実行ファイルのsymlinkを解決し、親の親にskills/がある配布root、または実行ファイルから上方のskills/を持つrootのskills/とskill-data/を使う。Dart起動では実行package URIからpackage rootを解決するfallbackを持ち、呼出元cwdから別packageを選ばない。install/upgrade済みバイナリは、自身に記録された実行ファイル隣接のバージョン別bundleを通常探索より優先する。そのbundleが失われた場合に別版へfallbackしない。

install/upgradeは指定checkoutの両ディレクトリをbin-directory内の専用`.marionette-agent-*` bundleへコピーしてからコンパイルする。相対bundle名だけをバイナリへ埋め込み、成功したバイナリを配置するため、ソースcheckoutなしでも移動可能。配布時はバイナリと対応する隠しbundleを一緒に運ぶ。失敗時は新bundleと自身の予約先を回収し、upgrade前のバイナリを保持する。旧bundleは実行中の旧版との整合性のため自動削除しない。手動コンパイルではskills/・skill-data/とbin/を持つ配布rootを用意するか、環境変数で明示する。コピー元のsymlink・特殊ファイルは自己完結した配布を保証できないため拒否する。

互換性のためskillsだけは`{"success":true,"data":...}`、失敗は`{"success":false,"error":"説明"}`。listはname/descriptionの配列、getはname/contentの配列（--fullで補助ファイルがあればfilesのpath/content配列）、pathはpaths配列を持つobjectまたはname/path object。専用helpはdata.help。session/schemaVersion/outcomeを付けない。text失敗はstderr、JSON結果はstdoutへ1 object。成功0、skillsと識別された引数エラー・未知名・探索失敗・期限切れは1。通常コマンドのJSON/終了値は変更しない。共通timeoutを読取前後で確認し、同期filesystem I/Oの即時中断は保証しない。

## 対象外・将来範囲

role/label/placeholderはfindに対応し、get value/is enabled/is checkedを追加した。通常selectorはkey/identifier/text/typeのまま維持する。hint/tooltip、完全なSemanticsツリー、永続的target IDは未対応。[Issue #14設計案](semantics-selector-state-design.md)は元のstock binding調査と将来設計として保持する。

record以外のAndroid／実機・他ホストOSの正式対応、iOS実機録画、Linux／Windows録画、アプリ起動管理、任意拡張CLI、hot reload/restart、long-press／pinch、任意のアプリ状態復元は対象外。workflow v1のschemaとMCP対象外の方針は維持する。

## Flutter向け拡張

[追加コマンド仕様](ja/cli-parity.ja.md)を本仕様の一部とする。snapshotのinteractive/compact/depth、型付きget/is、find、追加interaction、ref/時間wait、crop/diff、clipboard、config/namespace、接続state、batch/policy、record restart/fps、device list、doctor追加モード、install/upgradeの構文・出力・対応範囲を定義する。

任意の `marionette_agent_flutter` providerがある場合だけmounted Widgetの型付き観測へ切り替える。source不明の属性を推測しない。refの照合・一意性・送信直前の失効・自動再送禁止は既存契約を共用する。UI操作とrole/label等の検索はproviderが示す適用範囲に限定し、再観測と送信の原子性や全clip／被覆検出は保証しない。

IPC protocolVersionは6。要求に任意のsession action policyを追加した。public schemaVersionは1を維持し、新規コマンドのdataだけを拡張する。旧daemonは旧CLIでcloseしてから新CLIへ切り替える。


## 端末画面録画

`record`はFlutterの描画ではなく端末／ディスプレイ全体を収録する。VM ServiceやMarionette bindingに依存せず、releaseアプリやアプリ外の画面も対象にできる。OSが保護するコンテンツは保証しない。音声は収録しない。

| platform | device | 形式・前提 |
| --- | --- | --- |
| ios | 起動済みiOS SimulatorのUDID | `.mp4`、macOSとXcode。iOS実機・`booted`のような曖昧な別名は未対応 |
| android | オンライン・認証済みadb serial | `.mp4`、Android platform-tools。Emulator／実機の標準screenrecord |
| macos | 1から始まるディスプレイ番号 | `.mov`、macOS標準screencaptureと実行元アプリの画面収録許可 |
| web | `display:<index>@ws://127.0.0.1:<port>/devtools/page/<id>` | `.mov`、macOSと可視Chrome、専用debug profileと画面収録許可。明示したディスプレイ全体 |
| linux / windows | 任意 | 未対応。内部APIがUNSUPPORTED_CAPABILITYをthrowし、CLIは終了コード6を返す |

- platform/device/pathは必須。未知platform、deviceの構文不正、拡張子不一致はINVALID_ARGUMENT。未対応platformはCLI側でも検証し、daemon起動前に拒否する。
- 相対pathは呼出元CLIのcwdで絶対pathへ変換する。親directoryは既存かつ書込可能であること。既存file/directory/symlinkはIO_ERRORとして拒否し、自動上書きしない。
- sessionごとに同時に1録画、同一daemon内の端末ごとに1録画。開始中・停止処理中も予約し、競合はSESSION_CONFLICT。同じsessionで停止後に新しい保存先へ録画を開始できる。
- startはdaemonを必要に応じて起動し、録画所有者としてsessionを保持する。未接続の録画sessionの接続状態はdisconnected、URIはnull。録画開始が成功したsessionはcloseまで保持する。
- startは開始確認後に返り、録画自体はsession queueを占有しない。iOSは最初のフレームの通知、Androidは出力headerの生成を確認する。macOS標準コマンドにはfirst-frame通知がないため起動後1秒の生存を確認し、実際の動画生成はstopで検証する。
- `--timeout`は開始・停止要求の期限で、録画時間の上限ではない。開始のbackend待ちは最大30秒。開始が期限切れになった場合も、遅れて生成されたhandleの停止・予約回収を継続し、終了確認までは同じ端末を再利用しない。停止要求が期限切れになっても有界な停止・回収は続き、statusで結果を確認する。TIMEOUTはoutcome:unknownとなる。UI操作や録画を自動再送しない。
- Androidは180秒で自動停止し、ホストへ動画を回収して状態を更新する。分割・自動再開・結合は行わない。回転中の正しい収録は保証しない。
- stopは録画プロセス終了・動画確定・必要な回収・保存まで待つ。確定した停止・保存失敗はoutcome:failed、期限切れはoutcome:unknownとする。重複stopは同じ結果を返す。録画がなければ`{recordingState: idle}`。daemonがないstatus/stopでは新daemonを起動しない。
- recordの開始・停止・照会はrefを失効させず、VM Service接続を変更しない。hot restartや接続断でも端末録画は継続できる。
- closeは録画を確定してから接続を破棄し、data.recordingに最終状態を含める。既に録画が失敗していてもcloseは所有者を解放し、recordingState:failedと失敗情報を返す。
- daemon正常終了（SIGINT/SIGTERMを含む）は録画確定を最大60秒待つ。期限超過時は所有する録画プロセスを強制停止し、追加の後処理待ちは最大5秒で打ち切る。未確定動画と予約先は復旧用に保持し、成功扱いにしない。遅れて返った開始handleも強制停止する。OS内で進行中のファイルI/Oの取り消しや、切断されたAndroid端末の強制停止は保証できない。SIGKILL、ホスト停止後の自動復元は対象外。

成功dataはrecordingState（idle/starting/recording/stopping/stopped/failed）、platform、device、path、startedAt、elapsedMs、bytesを持つ。idleはrecordingStateのみ。startedAtは開始確認時のUTC日時、elapsedMsはそこから確定までの壁時計経過時間であり動画のメディアdurationではない。bytesは確定時の動画サイズ。失敗時のstatusにはfailureとrecoveryPathを含める。stopは失敗を非0終了で返す。

保存は内部パッケージがdaemon内で担当し、動画はIPCで転送しない。出力先を排他的に予約して同じ親directoryのprivate stagingへ録画し、確定後に予約先へ書き込む。開始失敗時はこの要求の予約を回収し、確定失敗時はstagingを復旧用に保持する。予約後に別プロセスが意図的に保存先を差し替える競合までは保証しない。

検証状況: iOS Simulator／Android Emulator／macOSメインディスプレイを製品CLIで確認済み。macOSではstart・status・stop・重複stop・既存file拒否・closeによる確定と、生成MOVの全フレーム復号・画面変化を確認した。

### Web録画の範囲と接続

WebはmacOS上の可視Google Chromeを対象とする。deviceは1〜999のdisplay番号と、Chromeの`/json/list`から選んだpageのWebSocket endpointを`display:1@ws://127.0.0.1:9222/devtools/page/<ID>`形式で結ぶ。ポートは1〜65535、IDは大文字英数字。localhost、remote host、認証情報、query、fragment、browser/worker endpoint、先頭ゼロは受理しない。Chromeに専用`--user-data-dir`とloopbackの`--remote-debugging-port`を指定して利用者が起動する。Chrome以外・headless・macOS以外は未対応で、protocolの機能不足はUNSUPPORTED_CAPABILITY。debugging無効・接続拒否はCONNECTION_LOST、protocol拒否はIO_ERROR。サーバーの生メッセージは出力しない。

利用者が選んだディスプレイ全体を標準screencaptureでMOVへ録画する。Chromeのアドレスバー・タブ・設定画面、同じdisplayのOSダイアログや他アプリを含む。タブだけの映像、Flutter描画の録画、音声ではない。Chromeを指定displayへ配置するのは利用者の責任であり、CLIはウインドウ位置を変更・追従しない。別displayへ移動しても録画先は変わらない。隠れた／最小化したウインドウや別displayのdialogは写らず、覆っている画面が写る。保護コンテンツの録画は保証しない。

Chromeのpage identityをCDPで確認し、Inspector終了通知とWebSocket切断を監視する。captureはmacOS backendの開始確認・停止・権限と同じ契約。macOSの実行元アプリに画面収録許可が必要で、拒否や無効displayはIO_ERRORと設定確認hintを返す。許可を自動変更したり、権限dialogを迂回したりしない。Webの通常操作は利用者または既存ブラウザー操作手段で行い、Web向けtap/fillを追加しない。VM Serviceに依存せず、record中の通常CLI操作も妨げない。

対象タブの終了・クラッシュ・debug接続断はCONNECTION_LOSTとして録画を終了し、statusをfailedへ更新する。stopは非0、closeはfailureを含む最終状態を返す。部分動画はrecoveryPathに保持し、別タブへ切り替えて成功扱いにはしない。明示的なstop/closeは通常確定する。開始・停止中の競合と期限超過は共通契約に従う。同一daemonの同一displayはWebの別タブとmacos録画を含めて排他。別daemonや外部レコーダーとの排他は保証しない。

API比較・選定理由と参照元は[Web録画方式](web-recording.md)を参照。

Web開始時はCoreGraphicsの`CGPreflightScreenCaptureAccess`をDart FFIで読み取り、未許可ならChrome接続・native録画の前にIO_ERRORで拒否する。許可要求APIは呼ばない。APIを利用できない環境はUNSUPPORTED_CAPABILITYとする。
