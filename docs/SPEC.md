# marionette_agent — 製品仕様

状態: `marionette_agent 0.0.1` の実装済み契約。単独コマンドとworkflow v1を含む。利用方法の詳細は[日本語CLIリファレンス](ja/cli-reference.ja.md)、内部の実装境界は[アーキテクチャ](ARCHITECTURE.md)を参照する。

## 目的と対象

Dart製CLIから、Marionette対応FlutterアプリをAI Agentが観測・操作できるようにする。agent-browserのsession、snapshot、短い要素参照、構造化出力という操作体系を採用する。ブラウザー固有のコマンド互換性は目的に含めない。

初版の実行ホストはmacOS、主なUI操作対象はiOS Simulator内の起動済みFlutterアプリ。recordは別途iOS Simulator／Android／macOSディスプレイを対象とする。アプリはdebug実行され、`marionette_flutter` のbindingが初期化済みで、接続可能なVM Service URIが必要。Simulatorやアプリの起動・ビルド・インストールは利用者側で行う。

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
| `--session <name>` | 省略時は `default`。英数字で始まる英数字・`_`・`-`、最大64文字 |
| `--json` | stdoutへ1つのJSONオブジェクトを出力 |
| `--timeout <ms>` | DurationとDateTimeで表現可能な正の整数。既定30,000ms。待ち行列・接続・処理を含む期限。範囲外はINVALID_ARGUMENT |
| `--content-boundaries` | 値なしflag、既定無効。snapshot要素／logs entryを未信頼コンテンツとして識別 |
| `--max-output <chars>` | 正の整数、既定無制限。snapshot／logsの項目列をUnicode code point数で制限 |
| `--idle-timeout <duration>` | daemon全体のidle期限。既定1h、0で無効。整数msまたはms/s/m/h接尾辞 |
| `--help` / `--version` | 接続なしで利用可能 |

共通オプションはサブコマンドの前後で受け付ける。同じオプションの重複は引数エラー。対話入力は要求しない。通常出力は簡潔なテキスト、診断ログはstderr。引数不足は非ゼロで終了し、使用可能な構文を示す。

構文エラーでも、有効に指定されたsessionとJSONモードを応答へ反映する。オプションの値や`--`以降にある文字列を共通オプションとして解釈しない。

### 共通安全オプション

共通オプションの定義・既定値・登録・値検証・構文エラーの出力モード回復は`cli/common_options.dart`を唯一の正本とし、全サブコマンドはrootの同じ定義を継承する。新しい3オプションもhelp/version、workflow、recordで受理する。重複・欠損・不正値はINVALID_ARGUMENT。環境変数や設定ファイルのfallbackはない。

`--content-boundaries`はsnapshotの要素行とlogsのentryだけを`--- BEGIN UNTRUSTED <source> <nonce> ---`／`--- END UNTRUSTED <source> <nonce> ---`で囲む。sourceは`snapshot`または`logs`、nonceはCLI呼出しごとにRandom.secureから生成する128bitの小文字hex。見出し、件数、エラー、hint、診断は外側に置く。JSONは文字列を変更せず、対象dataの`contentBoundary: {nonce, source}`へ同じ境界情報を格納する。内容の無害化や命令判定ではない。

`--max-output`は公開観測・generation・全要素のref採番を確定してから、elements／entriesの先頭から収まる完全な項目だけを返す。textはsnapshot要素行またはJSON化したlog entry、JSONは各項目のcompact JSONをcode pointで数える。項目間の改行／commaは各1文字として含め、包絡、配列括弧、見出し、境界、件数metadataは含めない。最初の項目が収まらなければ空配列。設定時は同じdataに`truncated`（bool）、`originalCount`、`omittedCount`を常に追加する。省略したrefはsessionから削除し、番号の推測利用はSTALE_REF。次回snapshotでも採番を巻き戻さない。workflowのfinalSnapshotも同じ契約。画像base64、保存画像、stderr診断、IPCの64MiB上限には適用しない。

idle timeoutは起動時に確定しdaemonの寿命中は変更しない。`10s`、`3m`、`1h`、`10000`（ms）、`10ms`を受理し、負数・小数・未知単位・Duration／DateTime範囲外はINVALID_ARGUMENT。省略した呼出しは稼働値を引き継ぐ。異なる値を明示したIPC呼出しはhandshakeで処理送信前にINVALID_ARGUMENT／not_sentとなる。同時起動も起動lockの取得後に再照合し、最初に確定した設定だけを使う。help/version、workflow schema/validateはローカルで完了しdaemonへ接触しない。

全session queueと要求の配送がidleになってから計測し、実行中・queue待ち中の処理は中断しない。health probeは終了を妨げない範囲で待ち、利用者の無操作時間を更新しない。期限到達時は通常のshutdownで録画を確定し、全接続・refを破棄してsocket・寿命lockを解放する。録画だけが継続していても要求queueがidleなら終了対象。次のアプリ操作はNOT_CONNECTEDとなり、明示的なconnectと新snapshotが必要。Flutterアプリ自体は終了しない。

### 実装済みコマンド

| コマンド | 動作 |
| --- | --- |
| `connect <uri>` | 指定sessionで接続。HTTP(S)のVM Service URIもWS(S)へ正規化 |
| `session list` | sessionの名前・接続状態を一覧表示。daemon不在時は空一覧 |
| `session show` | 選択sessionの状態、秘匿済み接続先、snapshotの有効性を返す |
| `close` | 録画があれば確定し、選択sessionを切断・破棄。対象不在も成功。Flutterアプリは終了しない |
| `snapshot` | 観測を更新し、要素一覧とrefを返す |
| `tap <ref>` / `tap <selector>` | 対象を1回タップ |
| `tap --x <n> --y <n>` | 明示座標を1回タップ |
| `fill <ref> <text>` / `fill <selector> <text>` | 入力欄の内容を置換。空文字でクリア |
| `swipe <ref> <direction> [--distance <n>]` | 要素を起点にスワイプ。selectorも使用可能 |
| `swipe --start-x <n> --start-y <n> --end-x <n> --end-y <n>` | 明示した始点から終点へスワイプ |
| `scroll <ref> <direction> [--distance <n>]` | スクロール領域への方向付きジェスチャー。selectorも使用可能 |
| `wait <selector> [--state exists\|gone] [--poll-interval <ms>]` | 要素の出現または消失を観測だけで待つ |
| `screenshot [--annotate] [path]` | PNGを排他的に保存。注釈は対応を検証できるproviderと直近の有効snapshotが必要 |
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

### snapshotと要素参照

snapshotは観測世代と要素一覧を返す。各要素には取得可能なtype、text、key、identifier、bounds、visibleを含める。存在しない属性は捏造しない。テキスト出力には対象選択に必要な情報を優先し、診断プロパティ全量を載せない。

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

JSONは成功・失敗とも以下の包絡形式。schemaVersionは初版で1。session非依存コマンドではsessionはnull。dataとerrorの一方だけを非nullとする。help/versionもJSONモードでは同じ包絡形式を使う。

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

screenshotのdataはpaths配列。複数画像は連番で保存し、通常利用で既存ファイルの上書きを避けるため、全保存先を排他的に作成してから画像を書き込む。既存のファイル・ディレクトリ・symlinkは拒否する。意図的な競合プロセスによる、保存先の予約後の差し替えまでは保証しない。画像が空なら失敗。logsは返された範囲を正規化し、収集未設定と0件を識別できない場合、その制約を伝える。URIの認証部分や入力文字列を診断ログへ出力しない。

`screenshot --annotate`は、直近snapshotで実際に公開された操作可能refだけを`@eN`ラベルと枠として新しいPNGへ合成する。既存PNGを入力に取らず、元画像のbytesも変更しない。保存先は注釈画像の新規pathであり、通常のscreenshotと同じ排他的保存・全体deadlineを使う。成功dataはpathsに加えてannotated=true、generation、annotationCount、skippedAnnotationsを返す。refの採番・更新・失効は行わない。snapshotが無効、またはcapture前後の再観測で対象の一意性・属性が変わった場合はSTALE_REFとし、画像を保存しない。観測とcaptureは上流APIでは原子的でないため、途中で変化して元へ戻るアニメーションまで検出する保証はない。静止した画面で使用する。

固定`marionette_flutter: 0.6.0`の通常screenshot応答だけでは、画像とview、倍率、向きの対応を検証できない。注釈には別途opt-inの`marionette_agent.captureMappedScreenshot` providerが必要である。これは画像とgeometry v1を同時に返す限定契約であり、固定binding一般の注釈対応を意味しない。exampleのdebug構成はこのproviderを実装する。単一view、原点(0,0)、論理boundsに対する回転0、明示した論理幅・高さとPNG幅・高さだけを対応対象とする。portrait/landscapeは各時点の寸法を使い、画像を回転推測しない。未登録、複数view/画像、回転、寸法不一致などはUNSUPPORTED_CAPABILITYとし、注釈を保存しない。倍率をboundsや画像の外観から推測しない。

boundsが欠損・非有限ならmissing_or_invalid_bounds、幅/高さが非正または一部でもview外ならbounds_outside_viewとしてそのrefを省略し、skippedAnnotationsへ記録する。boundsを画面内へclampしない。ラベルは互いに重ならない位置へ配置し、移動したラベルは線で対象に結ぶ。配置領域不足はlabel_space_exhaustedとして省略する。操作可能refが0件でも有効snapshotとgeometryがあればannotationCount=0で保存できる。

## 検証基準

1. macOSからiOS Simulatorに接続し、別々のCLIプロセスでsnapshot→tap／fill／swipe→snapshotが成立する。
2. 2つのsessionの接続・ref・切断が分離され、同一sessionの並行要求が直列化される。
3. 古いref、曖昧な対象、通信断、timeoutが規定のJSONと終了コードになり、操作が自動再送されない。
4. PageViewの切替とDismissibleのdismissをswipeで確認し、座標方式もSimulatorで検証する。
5. wait、scroll、PNG保存、ログ取得が共通のsession・deadline・エラー契約を通して動作する。
6. workflowのJSON／YAML検証、binding、queue占有、wait、停止時の進捗、最終snapshot引き継ぎを自動テストとSimulatorで確認する。
7. コード変更時は`packages/marionette_agent`でformat、analyze、関連testを実行する。CLI契約を変えた場合は`example/`をiOS Simulatorで起動し、製品CLIの結果と操作後の画面状態を確認する。

単体・IPC・契約テストは`packages/marionette_agent/test/`、Simulatorシナリオは`packages/marionette_agent/integration_test/`に置く。FakeBackendの成功だけをSimulator検証の代替にはしない。

## 対象外・将来範囲

record以外のAndroid／実機対応、他ホストOSの正式対応、iOS実機録画、Web／Linux／Windows録画、アプリ起動管理、任意の独自拡張を呼び出すCLI、hot reload/restart、double-tap／long-press／pinch、キー入力、scroll-to、session永続復元。注釈画像に必要な固定名のgeometry providerのみbackend内部の限定例外とする。workflowの条件分岐、loop、並列実行、include、任意コード実行、screenshot／logs組み込みもv1の対象外。MCP対応は本プロジェクトの対象に含めない。

## 端末画面録画

`record`はFlutterの描画ではなく端末／ディスプレイ全体を収録する。VM ServiceやMarionette bindingに依存せず、releaseアプリやアプリ外の画面も対象にできる。OSが保護するコンテンツは保証しない。音声は収録しない。

| platform | device | 形式・前提 |
| --- | --- | --- |
| ios | 起動済みiOS SimulatorのUDID | `.mp4`、macOSとXcode。iOS実機・`booted`のような曖昧な別名は未対応 |
| android | オンライン・認証済みadb serial | `.mp4`、Android platform-tools。Emulator／実機の標準screenrecord |
| macos | 1から始まるディスプレイ番号 | `.mov`、macOS標準screencaptureと実行元アプリの画面収録許可 |
| web / linux / windows | 任意 | 未対応。内部APIがUNSUPPORTED_CAPABILITYをthrowし、CLIは終了コード6を返す |

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
