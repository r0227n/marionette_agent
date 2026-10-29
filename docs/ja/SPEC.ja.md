<a id="marionette_agent--product-specification"></a>
<a id="marionette_agent--製品仕様"></a>

# marionette_agent — 製品仕様

[English](../SPEC.md) · [日本語の目次](README.md)

<a id="environment-diagnostics-doctor-issue-9"></a>
<a id="環境診断-doctor-issue-9"></a>

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
- `host.os`: macOS。`host.dart`: 実行SDKが>=3.13.7 <4.0.0。
- `runtime.socketPath`: 既存runtimeと同じ絶対path/80 UTF-8 bytes上限、socket `/s` のbyte数。
- `runtime.directory`: symlink不可、現在user所有、0700。不存在はskippedで作成しない。
- `daemon.ipc`: 安全確認済みdirectoryのsocketに受動接続、protocolVersion一致とreadyを確認。
  不在はskipped、拒否/不一致はfailure、無応答はunknown。最大1秒か残り期限の短い方。
- `dependencies.fixed`: CLI packageのmarionette_mcp、image、yamlのlock済みversionがpubspec制約（caret範囲を含む）を満たすか検査する。
  ファイル不在/取得不可はunknown。実bindingやインストール済み実体のversion保証ではない。
- `simulators.ios`: `xcrun simctl list devices available --json`でiOS端末の名前/UDID/runtime/stateを観測。
  0台はfailure、照会失敗はunknown。起動/修復はしない。
- `probe.vmService`: `--probe-uri`指定時だけ独立したVM clientを作成し、getVersion/getVM/getIsolateと
  登録済み`ext.flutter.marionette.getVersion`だけを照会。未指定はskipped、接続/RPC異常はfailure、
  timeoutはunknown。binding versionは有効な応答がある時だけ、capabilityは実際に登録されたextension名のみ。
  未観測versionはnull/unknown、未観測bindingはunknown。登録確認は操作成功の保証ではない。

probeの認証URI・remote exception・入力文字列は結果/診断へ出力しない。probe終了/失敗/期限切れでは
独立接続を解放し、遅れて成立した接続も閉じる。外部照会processは期限切れで終了させる。

状態: `marionette_agent 1.1.0` の実装済み契約。単独コマンドとworkflow v1を含む。利用方法は[日本語サイト](https://r0227n.github.io/marionette_agent/ja/)、詳細な実行契約は[補足](cli-reference.ja.md)、内部の実装境界は[アーキテクチャ](ARCHITECTURE.ja.md)を参照する。

<a id="purpose-and-scope"></a>
<a id="目的と対象"></a>

## 目的と対象

Dart製CLIから、Marionette対応FlutterアプリをAI Agentが観測・操作できるようにする。agent-browserのsession、snapshot、短い要素参照、構造化出力という操作体系を採用する。ブラウザー固有のコマンド互換性は目的に含めない。

初版の実行ホストはmacOS、主なUI操作対象はiOS Simulator内の起動済みFlutterアプリ。recordは別途iOS Simulator／Android／macOSディスプレイ（ChromeのWeb検証を含む）を対象とする。アプリはdebug実行され、`marionette_flutter` のbindingが初期化済みで、接続可能なVM Service URIが必要。手動起動へのconnectに加えて、launchでtester／iOS／Android／macOS／Webのヘッドレス環境を明示選択して起動できる。

stdio MCPサーバーを提供し、MCPクライアントからも既存CLIの操作体系を利用できる。`marionette_mcp` のDart接続実装をライブラリーとして利用し、VM Service経由でFlutter拡張を呼び出す。MCPクライアント製品とHTTP transportの提供は対象外。

native端末コマンドは、iOS SimulatorとAndroidの前面OS UIを観測・操作し、権限ダイアログや写真ピッカーにも対応する。VM接続は不要。[ネイティブ端末UI](#native-ui)を参照。

<a id="terminology"></a>
<a id="用語"></a>

## 用語

| 用語 | 意味 |
| --- | --- |
| session | 名前で選ぶ、1つのFlutterアプリへの接続と観測状態の単位 |
| daemon | sessionの接続と参照をコマンド間で保持するローカル常駐プロセス |
| snapshot | Marionetteから取得した操作可能要素・可読情報の観測結果。完全なWidgetツリーではない |
| ref | snapshot内の要素を指定する `@e1` 形式の短い参照 |
| selector | key・identifier・text・typeのいずれかによる明示的な対象指定 |

<a id="cli-contract"></a>
<a id="cli契約"></a>

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
marionette-agent --session demo screenshot ./screen.png --device "$SIMULATOR_UDID" --timeout 120000
marionette-agent --session demo close
```

refは例示。実行時には直近snapshotに返されたものを使う。

<a id="common-options"></a>
<a id="共通オプション"></a>

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

構文エラーでも、有効に選択されたsession（環境値を含む）とJSONモードを応答へ反映する。`close --all`は引数エラーを含めsession:nullとする。不正なsessionはnull、session非依存コマンドもnullとする。オプションの値や`--`以降にある文字列を共通オプションとして解釈しない。

`--debug`は構文エラーを含めopt-inで診断を追加し、通常診断とstdoutの既存envelopeは維持する。CLIからdaemonへ要求単位で伝え、並行sessionで設定・診断を共有しない。処理段階はCLI解析、runtime準備、daemon接続・起動・ready、送信、dispatch、session queue、command実行、結果。各プロセス内の処理区間開始からの単調な経過時間をmsで表示し、結果には成功の`OK`または正規化error codeを付ける。認証URI、fill入力、selector値、アプリ表示text、error message/details、stack traceは詳細診断に含めない。

<a id="common-safety-options"></a>
<a id="共通安全オプション"></a>

### 共通安全オプション

共通オプションの登録・CLI既定値・優先順位・構文エラーの出力モード回復は`cli/common_options.dart`を正本とし、全サブコマンドはrootの同じ定義を継承する。session名・期限・出力上限の値域検証とdaemon idle既定値は`protocol/protocol.dart`に定義し、CLIとIPCで共用する。`--debug`を含む共通オプションはhelp/version、workflow、recordで受理する。重複・欠損・不正値はINVALID_ARGUMENT。環境変数のfallbackはsessionとtimeoutだけに適用し、明示設定ファイルの値を環境変数より下位の既定値として使う。screenshot形式・品質は画像保存時だけ使用し、他コマンドの出力は変更しない。

`--content-boundaries`はsnapshotの要素行とlogsのentryだけを`--- BEGIN UNTRUSTED <source> <nonce> ---`／`--- END UNTRUSTED <source> <nonce> ---`で囲む。sourceは`snapshot`または`logs`、nonceはCLI呼出しごとにRandom.secureから生成する128bitの小文字hex。見出し、件数、エラー、hint、診断は外側に置く。JSONは文字列を変更せず、対象dataの`contentBoundary: {nonce, source}`へ同じ境界情報を格納する。内容の無害化や命令判定ではない。

`--max-output`は公開観測・generation・全要素のref採番を確定してから、elements／entriesの先頭から収まる完全な項目だけを返す。textはsnapshot要素行またはJSON化したlog entry、JSONは各項目のcompact JSONをcode pointで数える。項目間の改行／commaは各1文字として含め、包絡、配列括弧、見出し、境界、件数metadataは含めない。最初の項目が収まらなければ空配列。設定時は同じdataに`truncated`（bool）、`originalCount`、`omittedCount`を常に追加する。省略したrefはsessionから削除し、番号の推測利用はSTALE_REF。次回snapshotでも採番を巻き戻さない。workflowのfinalSnapshotも同じ契約。画像base64、保存画像、stderr診断、IPCの64MiB上限には適用しない。

idle timeoutは起動時に確定しdaemonの寿命中は変更しない。`10s`、`3m`、`1h`、`10000`（ms）、`10ms`を受理し、負数・小数・未知単位・Duration／DateTime範囲外はINVALID_ARGUMENT。省略した呼出しは稼働値を引き継ぐ。異なる値を明示したIPC呼出しはhandshakeで処理送信前にINVALID_ARGUMENT／not_sentとなる。同時起動も起動lockの取得後に再照合し、最初に確定した設定だけを使う。help/version、workflow schema/validateはローカルで完了しdaemonへ接触しない。

全session queueと要求の配送がidleになってから計測し、実行中・queue待ち中の処理は中断しない。health probeは終了を妨げない範囲で待ち、利用者の無操作時間を更新しない。期限到達時は通常のshutdownで録画を確定し、全接続・refを破棄してsocket・寿命lockを解放する。録画だけが継続していても要求queueがidleなら終了対象。次のアプリ操作はNOT_CONNECTEDとなり、明示的なconnectと新snapshotが必要。Flutterアプリ自体は終了しない。

<a id="implemented-commands"></a>
<a id="実装済みコマンド"></a>

### 実装済みコマンド

| コマンド | 動作 |
| --- | --- |
| `mcp [--tools <profiles>]` | stdio MCPサーバーを開始。既定core、複数profileをcommaで指定 |
| `connect <uri>` | 指定sessionで接続。HTTP(S)のVM Service URIもWS(S)へ正規化 |
| `skills [list]` / `skills get <name> [name...] [--full]` / `skills get --all [--full]` / `skills path [name]` | 同梱Skillの一覧・本文・既存pathをローカルで返す |
| `session list` | sessionの名前・接続状態を一覧表示。daemon不在時は空一覧 |
| `session show` | 選択sessionの状態、秘匿済み接続先、snapshotの有効性を返す |
| `close [--all]` | 録画があれば確定し、選択session（--allは全session）を切断・破棄。対象不在も成功。Flutterアプリは終了しない |
| `snapshot` | 観測を更新し、要素一覧とrefを返す |
| `session bind --platform ios\|android --device <id>` | 明示端末のnative前面画面を観測・操作する。Flutter接続は不要 |
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
| `screenshot --device <UDID> [--source <source>] [path]` | アプリ接続不要でXCUIScreenのPNG/JPEGを排他的に保存。 |
| `logs` | bindingで収集されたログを取得。購読や無期限の待機はしない |
| `record start <path> --platform <platform> --device <id>` | 端末画面録画を開始。VM Service接続は不要 |
| `record status` / `record stop` | 録画状態を照会／動画確定まで待って停止 |
| `workflow schema [action]` | workflow全体またはaction別の同梱JSON Schemaを返す。daemon・接続は不要 |
| `workflow validate <path>` | JSON／YAML workflowを読んで構文・schema・意味制約を検証。daemon・接続は不要 |
| `workflow run <path>` | 接続済みsessionでworkflowを1要求として直列実行 |

`<selector>` は `--key <value>`、`--identifier <value>`、`--text <value>`、`--type <value>` のいずれか1つ。例: `fill --key email 'a@example.com'`、`swipe --key pager left`。ref、selector、座標の混在はエラー。`wait`はselectorに加え、[Flutter向け拡張](#flutter向け拡張)のref待機・時間待機を受理する。座標は受理しない。workflow v1の対象はselectorだけである。identifier指定はbinding 0.7.0以降で対応し、それより古い版はUNSUPPORTED_CAPABILITYを返す。binding 0.1.0のselectorはkey/textのみで、座標tapも非対応である。

scrollは初版では指定領域を既存swipe機構で操作する。directionはswipeと同じく指の移動方向であり、コンテンツの移動先や到達保証ではない。画面外要素へのscroll-toは後続とする。

単独`wait`の`state`は`exists`が既定で、`gone`も指定できる。stateとpollIntervalMsの既定値はfield省略時だけ適用し、IPCでの明示null・不正型は観測前にINVALID_ARGUMENTとする。`poll-interval`は50〜1,000msの整数、既定100ms。最初の観測は即時に行い、全体期限は共通`--timeout`を使う。`exists`は一致が正確に1件かつ`visible != false`で成功し、複数一致はAMBIGUOUS_TARGET。`gone`は0件で成功し、1件以上なら待つ。text照合では由来未確認の候補も衝突へ含め、唯一の候補が由来未確認ならUNRESOLVABLE_TARGETとする。

`wait`は同一session queueで`inspect`だけをpollし、UI操作を送信せず、公開snapshot／refを発行・更新・失効しない。成功dataは待機した`state`と`requiresSnapshot:true`を返し、実際の画面状態と最新refを後続`snapshot`で確認するよう案内する。wait中のtimeoutまたは通信断はreadの既存契約どおり`outcome:not_sent`で接続世代とrefを破棄する。queue内で実行開始前に期限切れとなった要求は観測せず、接続とrefを維持する。

<a id="screenshot-format-and-persistence"></a>
<a id="screenshotの形式保存"></a>

### screenshotの形式・保存

- 注釈なしの既定PNGは復号検証後にbackendの元バイト列を保存し、寸法と透過を保持する。JPEGはCLI側でPNGを復号し、各画素のRGBを白背景へalpha合成してから不可逆圧縮する。寸法は変えない。PNG内の背景色指定は使用しない。
- `--screenshot-format`は小文字の`png`または`jpeg`。`--screenshot-quality`はJPEG指定時だけ0〜100の整数を受理し、既定90。固定encoderの品質0は最低品質1と同じ圧縮になる。品質100もlosslessではない。
- pathの拡張子はPNGなら`.png`、JPEGなら`.jpg`または`.jpeg`。大文字小文字を区別せず、指定した綴りは維持する。形式は拡張子から推測しない。不一致・未知の拡張子は接続前にINVALID_ARGUMENT。拡張子がなければPNGは`.png`、JPEGは`.jpg`を付加する。
- pathと`--screenshot-dir`を両方省略時は専用の非公開一時directoryに`screen.png`または`screen.jpg`を保存する。複数画像はbackendの順で、指定名の拡張子直前へ`-1`、`-2`…を付ける。例: `screen.jpeg`→`screen-1.jpeg`、`screen-2.jpeg`。自動名も同じ連番規則。
- 共通`--timeout`は取得・転送・復号・白背景合成・JPEG変換・保存を含む元の絶対期限。codec処理前後・合成中・保存中に期限を確認し、期限後に成功を返さない。同期codecや進行中のOS I/Oの即時中断は保証しない。
- 全画像の復号・変換が成功してから全保存先を排他的に予約し、書き込む。既存file/directory/symlinkはIO_ERRORで拒否する。途中の変換失敗は出力を作らず、予約・書込みの失敗やTIMEOUTではこの要求が作成した全fileと自動作成directoryの削除を試みる。既存fileを削除・上書きしない。OSがcleanupを拒否した場合は部分artifactが残る場合があり、成功pathsは返さない。意図的な予約後の差し替えは従来どおり保証外。

<a id="native-ios-screenshots"></a>
### iOSのネイティブ撮影（Issue #56）

`screenshot --device <UDID> [--source ios-simulator|ios-device] [path]`は、CLI同梱のXCTest runnerから`XCUIScreen.main.screenshot()`で端末main screenを撮影します。取得元の既定は`ios-simulator`です。Marionette/Flutter経由の静止画、ref/selector crop、注釈、mapped provider能力は削除しました。device未指定とsource `flutter`はINVALID_ARGUMENT、IPCのtarget/annotation fieldはUNSUPPORTED_CAPABILITYです。

Simulator撮影はmacOS、選択済みの完全なXcode、既定device set内で利用可能かつ起動済みのiOS SimulatorのUUID形式UDIDを必要とします。alias・名前・`booted`はINVALID_ARGUMENT、対象不在・停止はUNRESOLVABLE_TARGET、重複IDはAMBIGUOUS_TARGET、SDK不足はUNSUPPORTED_CAPABILITY、build/test/export/画像回収失敗はIO_ERROR、期限超過はTIMEOUTです。不正PNGはBACKEND_ERRORです。端末一覧と所有runnerの寿命管理には既存のSimulator管理機能を使い、画像取得にsimctl screenshotは使いません。

同梱の独立UI-test targetには対象アプリのtargetを設定せず、現在のmain screenだけをattachmentにします。対象アプリの起動・前面化、UIのtap、権限初期化、UI操作の再送は行いません。Flutter接続とアプリ側providerは不要です。最初の要求で非公開runnerをビルドし、daemonの存続中はそのbuildを再利用します。adapterとsessionのqueueで直列化し、待機中に期限切れになった要求はプロセスを開始しません。実行先UDIDを明示し、要求専用xcresultから名称と端末IDが一致するattachmentを正確に1枚回収します。不正・別端末・重複・symlink・サイズ超過を拒否し、成功・失敗時に結果の一時領域を削除します。timeoutでは所有driverを中断し、一意な所有runner bundleだけを終了します。disposeでbuildとインストールしたrunnerを片付けます。

共通`--timeout`はqueue、SDK検出、build/起動、test実行、attachment export、復号・変換・保存を含む単一の絶対期限です。初回build/起動には通常の既定値以上を要する場合があり、`--timeout 120000`で時間を確保できます。期限の更新とFlutter fallbackはありません。timeout応答後のcleanup中に進行中のOS I/Oが終了することがあります。

成功dataは`paths`と`capture:{source,method,device,runtime,display,scope,mask,coordinateSpace,pixelWidth,pixelHeight,orientation}`です。methodは`xcuiscreen`、displayは`main`、scopeは`device-screen`、maskは`system-default`、座標は`physical-pixels`です。Macウィンドウ倍率と独立した端末画素と表示中のOS UIを取得します。ノッチ・角丸maskの指定、回転・resize、Flutter座標への対応付けは行いません。寸法は返されたPNGから復号し、orientationはその縦横比です。横向きのXCUIScreen PNGが縦長の画素配列とEXIFの向き情報を持つ場合があり、JPEGでもその向き情報を保持します。保護された内容の取得は保証しません。

PNG/JPEG、品質、明示path > screenshot-dir > 非公開一時保存、排他的作成、期限、失敗cleanupは共通artifact writerを使います。成功時はrefを保持します。CLIの`diff screenshot --device <UDID> --baseline <PNG>`も同じ取得経路です。同じ端末・方式・向きで寸法の一致するbaselineを利用者が指定します。MCPではdeviceが必須で同じCLIを呼び、workflow screenshot stepもdeviceを必須として取得・保存・進捗契約を共用します。

`ios-device`はUNSUPPORTED_CAPABILITYです。実機runnerには開発署名・provisioning、pairing・信頼、必要なOSでのDeveloper Mode、互換Xcode/OSが必要ですが、これらの寿命管理は未実装・未検証で、対応する実機OSは宣言しません。Appleの[XCUIScreen API](https://developer.apple.com/documentation/xcuiautomation/xcuiscreen)、[実機設定](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)、[Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)を参照してください。

<a id="workflow-v1"></a>

### workflow v1

workflow v1はJSONまたは制限付きYAMLで`snapshot`、`tap`、`fill`、`swipe`、`scroll`、`wait`、`screenshot`を記述順に実行する。`run`は全stepを同一sessionの1つのqueue entryで実行し、最初の失敗で停止する。完了済みstepのrollback、自動retry、途中再開は行わない。

workflow内の操作対象はselectorだけを受理し、refと座標操作は受理しない。入力値は型付き参照でbindingし、文字列展開、環境変数展開、shell実行は行わない。`--timeout`はworkflow／inputsの読込、検証、daemonへの配送、queue待ち、全stepを含む絶対期限である。

成功時はworkflow名、完了step数、`requiresSnapshot`を返す。workflow内で最後に取得され、その後mutationされていないsnapshotがあれば`finalSnapshot`として返し、そのrefを後続CLIから利用できる。失敗時は`error.details`へ進捗の既知・未知、完了step数、失敗stepを付加する。詳細なfile schema、上限、waitの意味は[workflow v1仕様](workflow-file-spec.ja.md)を正本とする。

<a id="session-lifetime-and-races"></a>
<a id="sessionの寿命と競合"></a>

### sessionの寿命と競合

- connectまたはrecord startでdaemonを必要に応じて自動起動する。アプリ操作コマンドが未接続sessionを暗黙作成することはない。
- 同一session・同一URIへのconnectは、接続が正常なら成功。別URIへの付け替えにはcloseを先に実行する。
- sessionごとにコマンドを直列実行する。異なるsessionは独立する。同じ正規化URIを複数sessionで所有する要求は拒否する。URI別名による同一アプリの検出は保証しない。
- 通信断でsessionはdisconnectedとなりrefを失効する。明示的なconnectで復旧する。操作の自動再送はしない。
- daemon再起動で接続・snapshotを復元しない。最後のsessionを閉じたdaemonは終了する。
- タイムアウトしても送信済み操作を取り消せたとは限らない。結果不明を返し、接続を破棄して再接続と再観測を要求する。

単一sessionのcloseはbackendの切断完了まで要求期限内で待つ。確定した切断失敗はBACKEND_ERROR／failed（終了1）、完了未確認の期限超過はTIMEOUT／unknown（終了5）。どちらも接続所有権とrefを失効し、sessionを破棄する。所有アプリの終了通知が先に接続を破棄した場合も、同じ切断の完了結果を使用する。録画確定が期限超過した場合の保持・後処理は録画契約に従う。

<a id="state-queries-with-get"></a>
<a id="getによる状態照会"></a>

### getによる状態照会

`get text`と`get box`は対象を再観測し、操作と共通の一意性・ref属性比較を使用する。selectorが0件ならTARGET_NOT_FOUND、複数件ならAMBIGUOUS_TARGET、未発行／消失／属性変更したrefならSTALE_REF。単独の由来未確認text selectorはUNRESOLVABLE_TARGET。表示不可でも観測された属性は返せるため、操作専用のvisible判定は行わない。

成功dataはtextが`{"text":string|null}`、boxが`{"bounds":{"x":number,"y":number,"width":number,"height":number}|null,"unit":"flutter_logical_pixels"}`。boundsはFlutter論理座標であり、Simulator画像の物理pixelではない。欠損はnull、実際の空文字やゼロはそのまま返す。入力欄のvalue属性を取得する契約ではない。

`get count`の成功dataは`{"count":integer,"selector":{kind:value}}`。現在のinspect結果についてkey/identifier/text/typeの完全一致を数え、0件・複数件とも成功する。textはcandidateValueを使い、既知型と由来未確認型の観測textをそれぞれ1候補として数える。これは上流操作matcherの実一致数や操作可能性の保証ではない。refはINVALID_ARGUMENT、binding未対応selectorは件数にかかわらずUNSUPPORTED_CAPABILITY。成功した全getは公開snapshotの世代・refを更新／失効／再発行しない。timeout・通信断は既存read契約に従う。

<a id="is-visible"></a>

### is visible

`is visible <ref|selector>`は一度だけ対象を再観測する読み取りコマンド。成功のJSON `data`は`{"known":true,"value":true}`、`{"known":true,"value":false}`、`{"known":false,"value":null}`のいずれかとする。nullableなvisibleの未観測をfalseへ丸めない。textはそれぞれ`Visible: true`、`Visible: false`、`Visible: unknown`。

共通の対象再観測・一意性・属性比較を利用する。selectorの0件は`TARGET_NOT_FOUND`、複数件は`AMBIGUOUS_TARGET`、古いrefは`STALE_REF`、未対応selectorは`UNSUPPORTED_CAPABILITY`。非表示の一意な対象は成功してfalseを返す。成功時はUI操作、refの失効・再発行、公開snapshot世代の更新を行わない。待機やenabled/checkedの判定は含まない。


<a id="close---all"></a>

### close --all

`close --all`はdaemon全体の後始末。明示的な`--session`との併用（defaultも含む）はINVALID_ARGUMENT（exit 2）。daemon不在・空でも成功し、自動起動しない。成功はsession:null、data:{closed:true,sessions:[session別Result]}。名前順の各Resultは通常の包絡（session、ok、dataまたはerror）を使う。closedはローカルsessionの破棄を表し、アプリ終了を意味しない。

受付時に対象sessionを固定して全新規要求の受付を停止する。それ以前に予約したconnectも対象に含む。queue待ちは実行前にCONNECTION_LOST/not_sentとして拒否し、実行中は共通`--timeout`の絶対期限まで完了を待つ。期限到達で接続世代を失効し、送信済み操作の応答はCONNECTION_LOST/unknown、未送信はnot_sent。遅延完了によるref復活・後続操作の送信・UI再送を禁止する。

sessionごとに録画確定・切断を期限内で待つ。部分失敗でも全sessionのref・URI所有権を破棄しdaemonを終了する。部分失敗はdata:null、error.details:{closed:true,sessions:[session別Result]}。期限超過が1件でもあればTIMEOUT（exit 5）、それ以外の失敗はCLOSE_FAILED（exit 1）。集約outcomeは結果不明があればunknown、それ以外はfailed。各sessionに切断成功、失敗、期限超過を残す。IPC配送自体が途絶えた場合はunknownとなり、session別結果を推測しない。

停止中daemonへ送信した新規connectはCONNECTION_LOST/not_sent。handshakeが停止中なら既存の起動lock／寿命lock経路で次daemonを待つことがあるため、close --allは将来の明示connectを禁止する障壁ではない。次回利用は明示connectと新snapshotが必要。socket削除と寿命lock解放は既存shutdown経路を使い、応答配送はdeadline+250ms、残client破棄はshutdown後250msに制限する。録画の期限後cleanupには既存のshutdown上限（60秒とabort猶予5秒）を適用する。

<a id="snapshots-and-element-references"></a>
<a id="snapshotと要素参照"></a>

### snapshotと要素参照

snapshotは観測世代と要素一覧を返す。各要素には取得可能なtype、text、key、identifier、bounds、visibleを含める。存在しない属性は捏造しない。テキスト出力には対象選択に必要な情報を優先し、診断プロパティ全量を載せない。

`snapshot [--key <value> | --identifier <value> | --text <value> | --type <value>]`は省略可能なfilterを1つだけ受理する。値は空でない文字列で、観測属性との大文字小文字を区別した完全一致。複数selector、ref、未知option、空値はINVALID_ARGUMENTで観測前に拒否する。filterなしの出力は従来どおり。0件・複数件も成功した新snapshotであり、旧refはすべて失効する。

filterは観測用であり、`--text`は未知型を含む表示textにも一致する。`--identifier`もbackendの操作selector対応とは独立して観測済みidentifierに一致し、属性がなければ0件。表示textへの一致だけでは操作可能性を保証しない。操作には別途、対応確認済みselector・全観測結果での一意性・可視性の確認が必要となる。

処理順は全要素の観測→全体での一意性確認とref採番→filter→`--max-output`。filter外の衝突もref安全性に含め、番号は表示範囲で振り直さない。filter外・出力制限で省略されたrefは利用不可（STALE_REF）。filter時だけdataに`filter: {kind, value, matchedCount, totalCount}`を追加する。kindはkey/identifier/text/type、valueは指定文字列、totalCountは全観測要素数、matchedCountは出力制限前の一致数。text形式もFilter行に同じ条件・件数を返す。filter自体はtruncatedを意味しない。`--max-output`設定時のoriginalCountはfilter後の件数（matchedCount）、omittedCountはそのうち予算で省略した件数。filter metadataは文字数予算外。workflow v1のsnapshot step構文は変更しない。

refは選択sessionの直近snapshotだけで有効。新snapshot、再接続、切断で既存refを失効する。UI操作をバックエンドへ送る直前にも全refを失効し、成功・失敗・結果不明のいずれでも再snapshotを要求する。引数検証のみの失敗は失効させない。成功したwait、screenshot・logs・状態照会は失効させない。

ref番号はdaemonの生存期間を通して単調増加し、sessionをまたいでも再利用しない。daemon再起動後は必ずconnectとsnapshotからやり直す。

操作直前に再観測し、保存したselectorが一意に一致し、type・識別属性・text・boundsが観測時から変化していないことを確認する。不一致はSTALE_REF、複数一致はAMBIGUOUS_TARGET。refから座標への自動フォールバックは行わない。明示selectorでも観測内の一致数を確認する。

key、identifierを優先し、text・typeはバックエンドの照合との対応を確認できる場合に使う。表示用Semanticsテキストは照合用textと同義ではない。一意に操作できるselectorを構成できない要素は情報を表示するが、操作用refを付けず理由を返す。

stock bindingではtextの由来を区別する属性がないため、text照合は確認済みの型名Text・RichText・EditableText・TextField・TextFormFieldに限定する。Semanticsの派生型やその他の独自型のtextは表示情報として扱い、操作にはkeyまたは一意なtypeを使用する。

一意性の判定には由来未確認のtextも含める。同じtextを持つ未知の型が観測された場合、既知の型へのtext指定・text由来のref・wait existsもAMBIGUOUS_TARGETとして拒否する。snapshotは安全なkey/typeがあればそちらでrefを発行する。

既存APIでは再観測と操作は原子的ではなく、観測に含まれない要素もある。その間の画面変化や同一属性の別要素への置き換えを完全には検出できない。初版はこの制約下で事前検証を行い、Flutter要素の永続IDを保証しない。

<a id="swipe-details"></a>
<a id="swipeの詳細"></a>

### swipeの詳細

- 要素方式と座標方式の2方式。方向はleft・right・up・down。
- 距離は有限の正数、既定200。座標は有限の非負数。単位はFlutterの論理ピクセルであり、画像の物理ピクセルとは区別する。
- 座標方式は4座標をすべて必須とし、同一の始点・終点は拒否する。要素方式のオプションとの混在も拒否する。
- 速度・継続時間・慣性の指定、iOSホーム操作などのシステムジェスチャーは対象外。
- 成功はバックエンドのジェスチャー処理完了。ページ切替などの結果は次のsnapshotで確認する。

<a id="output-and-exit-codes"></a>
<a id="出力と終了コード"></a>

### 出力と終了コード

JSONは`skills`と稼働中の`mcp`を除き成功・失敗とも以下の包絡形式。schemaVersionは初版で1。session非依存コマンドではsessionはnull。dataとerrorの一方だけを非nullとする。help/versionもJSONモードでは同じ包絡形式を使う。`skills --help`を含むSkill配信の互換出力は後述の専用契約に従う。`mcp`の起動引数エラーは通常のCLI契約、起動後のstdoutはMCPメッセージ専用。

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

<a id="screenshot-storage"></a>
<a id="screenshotの保存"></a>

### screenshotの保存

screenshotのdataは絶対pathの`paths`配列。保存先は明示path、共通`--screenshot-dir <path>`、従来の非公開一時directoryの順に選ぶ。明示pathがあればdirectoryの存在や権限を調べず、その場所へ保存する。directory設定は呼出しごとで、daemon／sessionには保存せず、他コマンドの動作にも影響しない。空文字またはNULを含むdirectory指定はINVALID_ARGUMENT。

明示pathとdirectoryの相対pathは呼出元CLIのcwdを基準に正規化する。明示pathの親と指定directoryは事前作成を必須とし、自動作成しない。指定directoryの不存在、通常file、directory自身のsymlink（danglingを含む）、保存に必要な権限の不足はIO_ERROR。祖先directoryのsymlinkは解決を許す。directoryのtype確認後に意図的に差し替えられる競合までは保証しない。

directory指定時はその直下に`screen-<128bit乱数の32桁hex>.png`（JPEGは`.jpg`）を生成する。連続／同時撮影でも各要求で別名を生成し、排他的作成で上書きを防ぐ。万一生成名が既存pathと衝突した場合もIO_ERRORとして拒否する。両方省略時は従来どおり一意な`marionette-screenshot-*`一時directory内の`screen.png`または`screen.jpg`へ保存する。

複数画像は指定名／生成名の拡張子の前へ`-1`、`-2`の連番を付ける（拡張子なしは選択形式に応じて`.png`または`.jpg`を追加）。全PNGを復号検証し、全保存先を排他的に作成してから画像を書き込む。既存のfile・directory・symlinkは拒否する。途中失敗時はこの要求が作成した画像fileを削除し、一時保存の場合はこの要求の一時directoryも削除する。指定directoryと既存artifactは削除しない。cleanupの失敗で元のエラーを置き換えず、成功pathを返さない。保存先の予約後に別プロセスが意図的に差し替える競合までは保証しない。画像が空または不正PNGならBACKEND_ERROR、保存期限超過はTIMEOUT、その他の保存失敗はIO_ERROR。readであるscreenshotのこれらのエラーは従来どおりoutcome:not_sentとなる。

logsは返された範囲を正規化し、収集未設定と0件を識別できない場合、その制約を伝える。URIの認証部分や入力文字列を診断ログへ出力しない。

ref注釈と論理座標の対象cropは削除しました。OS画面撮影は上記native契約に従います。

<a id="verification-criteria"></a>
<a id="検証基準"></a>

## 検証基準

1. macOSからiOS Simulatorに接続し、別々のCLIプロセスでsnapshot→tap／fill／swipe→snapshotが成立する。
2. 2つのsessionの接続・ref・切断が分離され、同一sessionの並行要求が直列化される。
3. 古いref、曖昧な対象、通信断、timeoutが規定のJSONと終了コードになり、操作が自動再送されない。
4. PageViewの切替とDismissibleのdismissをswipeで確認し、座標方式もSimulatorで検証する。
5. wait、scroll、PNG/JPEG保存、ログ取得が共通のsession・deadline・エラー契約を通して動作する。
6. workflowのJSON／YAML検証、binding、queue占有、wait、停止時の進捗、最終snapshot引き継ぎを自動テストとSimulatorで確認する。
7. コード変更時はリポジトリルートでformat、analyze、関連testを実行する。CLI契約を変えた場合は`example/`をiOS Simulatorで起動し、製品CLIの結果と操作後の画面状態を確認する。

単体・IPC・契約テストは`test/`、Simulatorシナリオは`integration_test/`に置く。FakeBackendの成功だけをSimulator検証の代替にはしない。

<a id="bundled-skill-distribution"></a>
<a id="同梱skillの配信"></a>

## 同梱Skillの配信

`skills`はagent-browserの同梱Skill設計を採用するローカル読取コマンド。アプリ接続、runtime作成、daemon起動・照会、ダウンロード、Skillの生成やエージェント設定へのインストールを行わない。`--restore`やaction policyを実行せず、共通オプションの解析・値検証と`--debug`だけを共有する。batch/workflow/IPCの操作には追加しない。

- `skills`と`skills list`は名前順の一覧。textの説明は最大70 UTF-8 bytes付近の単語境界で省略し、JSONには全文を返す。
- `skills get <name> [name...]`は指定順でfrontmatterを含むSKILL.md全文を返す。`--full`は各Skillのreferences/、templates/直下の読めるテキストファイルを、ディレクトリ順・ファイル名順に追加する。再帰探索や実行はしない。
- `skills get --all`は非表示でない全Skillを名前順に取得。`--full`を併用可能。`--all`は名前指定より優先する。
- `skills path`は探索対象ディレクトリを1行ずつ、`skills path <name>`は名前に対応するSkillディレクトリを返す。ディレクトリ名ではなくfrontmatterのnameで検索する。
- `skills --help` / `-h`で専用help。`--json`はコマンドの前後で使用可能。共通契約の未知オプション・重複・余剰引数の検証を使用する。

`skills/marionette-agent/SKILL.md`は`hidden: true`の導入用stub。`skill-data/core/`・`skill-data/dogfood/`・`skill-data/simulator-verify/`が実行時ガイドで、それぞれ補助reference/templateも同梱する。英語のdogfoodガイドはFlutterの探索的QAを扱い、問題の分類基準と再現可能なレポートのテンプレートを含む。直下サブディレクトリのSKILL.mdからname・description・hiddenを簡易パースする。descriptionのインデント継続行は空白で連結、hiddenはtrue/yesを認識する。name欠損・空文字、frontmatter不正、読取不能なエントリは無視。frontmatterの開始・終了は独立した`---`行とし、LFとCRLFを受理する。hiddenはlist/--allから除外するが明示名でget/pathできる。空一覧は成功、get対象なしや未知名は失敗。重複nameは両方を一覧に残し、明示名では探索順の先頭を使う。

保存先の解決は、既存の`MARIONETTE_AGENT_SKILLS_DIR`（単独のSkill親ディレクトリ）を最優先する。不正・不存在のoverrideは通常探索へ戻す。通常は実行ファイルのsymlinkを解決し、親の親にskills/がある配布root、または実行ファイルから上方のskills/を持つrootのskills/とskill-data/を使う。Dart起動では実行package URIからpackage rootを解決するfallbackを持ち、呼出元cwdから別packageを選ばない。install/upgrade済みCLIは、実行ファイルのbinディレクトリに隣接するmarkerで版別bundleを識別する。そのbundle内のガイドが失われた場合に別版へfallbackしない。

install/upgradeは専用`.marionette-agent-*`版別ディレクトリ内にnative assets付きCLIをビルドする。ビルド後にガイドとnoticeを`bundle/bin/`・`bundle/lib/`の隣へコピーする。通常ファイルの実行用launcherがその版のCLI本体を選ぶため、launcherと隠しディレクトリ一式を一緒に配布する。bundle markerによりガイド欠落時に別版へfallbackしない。失敗時は新規版ディレクトリと自身の予約先を回収し、upgrade前のlauncherを保持する。実行中の旧版との整合性のため旧bundleは自動削除しない。手動ビルドでもnative assetsとガイドをbundle内に保持する。コピー元のsymlink・特殊ファイルは自己完結した配布を保証できないため拒否する。

互換性のためskillsだけは`{"success":true,"data":...}`、失敗は`{"success":false,"error":"説明"}`。listはname/descriptionの配列、getはname/contentの配列（--fullで補助ファイルがあればfilesのpath/content配列）、pathはpaths配列を持つobjectまたはname/path object。専用helpはdata.help。session/schemaVersion/outcomeを付けない。text失敗はstderr、JSON結果はstdoutへ1 object。成功0、skillsと識別された引数エラー・未知名・探索失敗・期限切れは1。`--config`の不存在・JSON不正・未知optionによる失敗もこの形式と終了値を使う。通常コマンドのJSON/終了値は変更しない。共通timeoutを読取前後で確認し、同期filesystem I/Oの即時中断は保証しない。

<a id="out-of-scope-and-future-work"></a>
<a id="対象外将来範囲"></a>

## 対象外・将来範囲

role/label/placeholderはfindに対応し、get value/is enabled/is checkedを追加した。通常selectorはkey/identifier/text/typeのまま維持する。hint/tooltip、完全なSemanticsツリー、永続的target IDは未対応。[Issue #14設計案](../semantics-selector-state-design.md)は元のstock binding調査と将来設計として保持する。

iOS／Android実機・他ホストOSの正式対応、iOS実機録画、Linux／Windows録画、任意拡張CLI、hot reload/restart、long-press／pinch、任意のアプリ状態復元は対象外。workflow v1のschemaは維持する。

<a id="stdio-mcp-server"></a>
<a id="stdio-mcpサーバー"></a>

## stdio MCPサーバー

`marionette-agent mcp [--tools core,inspect,actions,workflow,record|all]`は、`dart_mcp: 0.5.2`のサーバーAPIで改行区切りJSON-RPCを処理する。protocol versionの交渉、initialize／initialized、ping、stdioの切断処理はSDKに従う。起動・tool discoveryだけではdaemon／アプリを起動しない。初期化完了後にtools/listとtools/callを利用する。resources／prompts／HTTP transportは提供しない。

既定profileはcore。複数profileはcommaで合成し、重複は除く。allは公開済みの全MCPツールを有効にする（全CLI構文の互換性を意味しない）。未知／空profileはINVALID_ARGUMENT。tool名は`marionette_agent_` prefix。各profileの範囲と入力契約は[CLI実行の詳細](cli-reference.ja.md#mcp)を参照する。tools/listは最大20件ずつ返し、nextCursorで続きを取得する。未公開／無効なtoolと不正cursorはJSON-RPC -32602。toolには型付きinputSchemaとreadOnly／destructive／idempotent／openWorldのannotationsを付ける。

UI対象は`target: {ref: "@e1"}`またはkey／identifier／text／typeのうち1つを持つobject。共通fieldはsession、timeoutMs、maxOutput、contentBoundaries。tool fieldが起動時の共通オプション既定値を上書きする。namespace・action policy・confirm-actions・idle設定は起動時の指定を継承する。入力値をshellへ渡さず、固定CLIコマンドのargvへ変換する。自由なコマンド配列やextraArgsは公開しない。workflow／batchはfile path入力でありstdin `-`を拒否する。`--restore`と`--confirm-interactive`はMCP起動時に拒否する。

各tool callは同じ実行ファイル／Dart entrypointのCLIを`--json`付きで1回だけ起動する。CLIのsession、ref失効、queue、deadline、policyとerror outcomeを共用する。独立CLIから同じruntime/sessionを利用できる。CLIを呼ぶtoolの成功・失敗はtextと`structuredContent: {exitCode, response}`へ格納し、responseにCLIの包絡を保持する。非0終了またはok:falseはisError:true。入力schema不適合は値をechoせずINVALID_ARGUMENT。CLI起動失敗はIO_ERROR／not_sent、起動後の応答不備やMCP側期限超過はIO_ERRORまたはTIMEOUT／unknownとし、自動再送しない。CLI実行には要求timeoutに5秒の起動・回収猶予を加え、CLI自身のdeadlineは変更しない。stdout捕捉上限は64MiB。tools_profilesだけはCLIを呼ばずprofile情報を直接返す。

screenshotは保存pathを含むCLI包絡に加えてPNG／JPEGのMCP ImageContentを返す。画像は合計16MiBまで。超過・読込失敗時は保存結果を保持し、textでinline画像の省略を伝える。snapshot／logsのアプリ由来内容は未信頼データである。

MCP通信内容や認証URI・入力文字列を診断ログへ記録しない。子CLIのstderrはMCP応答へ転送しない。stdin EOFはMCPサーバーと所有する実行中CLIを終了する。独立daemonと既存sessionは通常CLIと同じ寿命を持ち、接続を閉じるにはcloseを呼ぶ。SDKのcancellationは未対応のため、途中切断で実行済み操作を取り消したとはみなさない。

<a id="flutter-extensions"></a>
<a id="flutter向け拡張"></a>

## Flutter向け拡張

[追加コマンド仕様](cli-parity.ja.md)を本仕様の一部とする。snapshotのinteractive/compact/depth、型付きget/is、find、追加interaction、ref/時間wait、crop/diff、clipboard、config/namespace、接続state、batch/policy、record restart/fps、device list、doctor追加モード、install/upgradeの構文・出力・対応範囲を定義する。

任意の `marionette_agent_flutter/flutter.dart` providerがある場合だけmounted Widgetの型付き観測へ切り替える。source不明の属性を推測しない。refの照合・一意性・送信直前の失効・自動再送禁止は既存契約を共用する。UI操作とrole/label等の検索はproviderが示す適用範囲に限定し、再観測と送信の原子性や全clip／被覆検出は保証しない。

IPC protocolVersionは7（管理対象アプリのlaunchとclose時終了を追加）。要求に任意のsession action policyを追加した。public schemaVersionは1を維持し、launchと所有アプリを表示するsession情報のdataを拡張する。旧daemonは旧CLIでcloseしてから新CLIへ切り替える。


<a id="device-screen-recording"></a>
<a id="端末画面録画"></a>

<a id="headless-flutter-app-recording-issue-20"></a>
<a id="flutterアプリのヘッドレス録画issue-20"></a>
<a id="web-recording-scope-and-connection"></a>
<a id="web録画の範囲と接続"></a>
## プラットフォームAPIによる録画

録画はMarionetteやVM Service接続を使いません。`--platform flutter`と録画専用接続を削除しました。取得失敗時にFlutterへフォールバックしません。ホストは同梱native動画ライブラリを利用できるmacOSです。

| platform | device | 取得方法と出力 |
| --- | --- | --- |
| ios | 起動済みSimulatorのUDID | 同梱の常駐XCTest runnerが`XCUIScreen.main.screenshot()`を呼ぶ。H.264 MP4 |
| android | 非公開のUI Automatorペアリングファイル | 既存のcapture instrumentationが`UiDevice.takeScreenshot`を呼ぶ。Emulatorのdisplay 0。H.264 MP4 |
| macos | 1始まりのactive display番号 | ScreenCaptureKitの`SCStream`と`SCRecordingOutput`。macOS 15以上・Xcode・画面収録許可。H.264 MOV |
| web | `ws://127.0.0.1:<port>/devtools/page/<ID>` | Chromium CDPの`Page.captureScreenshot`。headlessを含むpage viewport。H.264 MP4 |

platform・device・新規出力pathを必須とします。相対pathとAndroidのペアリングpathは呼出元cwd基準です。既存file・directory・symlinkを拒否します。録画はsessionを所有し、同一daemonの明示対象を終了確認まで予約します。Web pageはmacOS displayを予約しません。Android instrumentationはスクリーンショットと同じ手順で別途起動し、録画停止では終了させません。iOSはrunnerをbuild・所有しますが、観測対象アプリを起動しません。端末一覧とrunnerの後処理にsimctlを使う場合がありますが、画像・動画取得には使いません。adb screenrecordとscreencaptureによる録画も削除しています。

iOS/Android/WebはプラットフォームAPIからPNGを連続取得し、単調時計による実取得時刻でVFR動画へ変換します。native動画streamのfpsを保証する方式ではありません。`--fps 1..60`は取得後の待機間隔（既定10）で、取得・転送時間が加わり、高速アニメーションを取りこぼす場合があります。録画時間に応じた一時ディスク容量が必要です。寸法変更は失敗にします。macOSは最小フレーム間隔を指定（既定30fps）します。すべて無音で、保護コンテンツは保証しません。Webはbrowser chromeとOS dialogを含まず、iOS/Androidは端末画面を含みます。macOSは他アプリも含む選択displayを記録し、windowを追従しません。

開始は最初の有効PNGまたはScreenCaptureKitの録画開始callbackを確認します。要求期限はrunnerのbuild/startを含み、backendの開始待ちは最大120秒です。iOS初回は`--timeout 120000`を指定してください。stop/closeは確定・保存を待ち、重複stopは同じ結果を返します。restartは旧動画を確定してから新規保存先へ開始します。自動再開・取得元fallback・UI再送は行いません。取得エラーとChromium切断は録画失敗です。変換期限は30秒です。要求timeout後も有界cleanupを継続します。

状態はidle/starting/recording/stopping/stopped/failed。成功dataはplatform・device・path・startedAt・elapsedMs・bytesを含み、elapsedMsは再生時間ではなく壁時計時間です。失敗statusはfailureとrecoveryPathを含みます。排他的に予約した出力先と同じ親のprivate stagingへ書き込み、確定失敗では復旧データを保持します。shutdownは最大60秒待ち、強制cleanupを追加5秒で制限します。SIGKILL/host停止後の自動復元は対象外。操作ref・VM接続世代を変更しません。

Chromiumは専用debug profileとloopback remote debuggingを使い、`/json/list`の正確なpage endpointを指定します。portは1〜65535、IDは大文字英数字です。remote host・認証情報・query・browser endpoint・旧`display:N@`形式・MOV出力を拒否します。機能不足はUNSUPPORTED_CAPABILITY、切断はCONNECTION_LOST、拒否・不正画像はIO_ERROR。サーバーの生メッセージを公開しません。WebにmacOSの画面収録許可は不要です。Android実機・iOS実機は今回の対象外です。

<a id="hybrid-execution-environments-issue-20-extension"></a>
<a id="ハイブリッド実行環境issue-20追加仕様"></a>

## ハイブリッド実行環境（Issue #20追加仕様）

`launch <project> --platform tester|ios|android|macos|web`はmacOSホストで選んだ環境のdebugアプリをビルド・起動し、同じsessionへ接続して最初のinspectまで確認する。標準結果の接続情報にapplication:{platform,state,pid,device?}を追加する。session show/listでも所有アプリを表示する。URIは既存の秘匿契約に従う。

Flutter実行ファイルは--flutter（省略時daemon PATH）、entrypointは--target（既定lib/main.dart）。projectはCLIのcwdで絶対化する。iOSのみ--device-typeと--runtimeが必須、Androidのみ--avdと偶数--port（5554..5682）が必須。他環境のfieldと未知fieldはCLIとdaemonの両方で拒否する。SDK、AVD、project依存は利用者が事前準備し、launchは--no-pubを使う。要求timeoutはビルド・起動・接続・観測の全体期限。

launchはdaemon自動起動対象で、session queueとaction policyを共有する。既存接続・所有アプリ・録画があるsession、管理中project、利用中Android portはSESSION_CONFLICT。projectのビルド出力競合を防ぐため、同一projectは実pathとOSファイルlockで排他にする。別環境への自動fallback・操作再送・自動再起動はしない。

起動処理はmarionette_agent_platform_interfaceの契約とios/android/macos/web/flutterの実装パッケージで構成する。tester/web/macOSはFlutter runner、iOSは固有private device set、Androidは明示AVDの-no-window -no-snapshot -read-onlyプロセスを所有する。macOSアプリは非表示windowのopt-in対応を要する。CLIが対象実装の選択と共通lifecycleの調整を行い、対象別パッケージが環境変数やOSコマンドを組み立てる。

closeは録画を確定し、launchした環境を終了して接続を破棄する。外部アプリへのconnectは接続だけを閉じる。close --allとdaemon終了も所有資源を回収する。アプリ終了で接続世代とrefを失効する。起動・準備失敗やtimeout時は自己所有プロセス・端末・URIを回収する。回収は要求期限を越えて継続することがある。各processの終了は通常要求8秒、TERM3秒、KILL3秒、iOS端末回収は30秒以内。終了を確認できない場合は成功扱いにせず、一時領域を保持する。共有端末・adb serverには作用しない。SIGKILL・ホスト停止後の自動復元は対象外。

testerの対応SDKはFlutter 3.47.8、debugのみ。論理800×600、DPR 3。OS native機能・Webの実行意味・実機性能の同等性を保証せず、各実行環境で確認する。全環境の操作は既存sessionを共用する。録画には明示したnative対象が必要で、tester描画録画は削除した。手順と制約は[日本語ガイド](headless.ja.md)を参照。

<a id="android-emulator-screenshots"></a>
## Android Emulatorのスクリーンショット

`--source android-emulator --device <私有pairingファイル>`でUI Automatorの`UiDevice.takeScreenshot(File)`を選択する。既定はios-simulatorのままとする。CLI・MCP・screenshot workflow step・画像diffは既存の撮影serviceとartifact writerを使い、`native`操作コマンド・ref・UI操作は追加しない。pairing pathはIPC前に呼出元CLIのcwdで絶対化する。別途起動するInstrumentationがEmulatorの10.0.2.2から一時的なhost loopback listenerへ接続し、nonceを使う相互HMAC-SHA256で要求を認証する。撮影実装はADBコマンド・shell・port forwardingを実行しない。配布とInstrumentation起動はAndroid Studio／Gradleの別のテスト環境で行い、その環境はAndroid debugging transportを内部利用する。

ranchu/goldfishのEmulatorで、単一display 0だけを対象とする。pairingが明示的な論理端末identityを固定する。結果にはsource:android-emulator、method:uiautomator、pairingの端末名、runtime:android-emulator、display:0、scope:device-screen、mask:system-defaultと共通decoderが得た物理pixel寸法を返す。権限ダイアログ・picker・IME・system barを含む。AndroidはFLAG_SECUREの対象を隠すか撮影を拒否する場合があり、黒pixelだけで保護を確定しない。agent不在・期限切れ、認証、接続断、破損・過大出力は明示的に失敗し、別の取得元やUI再送へ切り替えない。PNGは32 MiBまで。準備は[captureガイド](https://r0227n.github.io/marionette_agent/ja/guides/capture/)を参照する。

<a id="native-ui"></a>

## ネイティブ端末UI

`session bind --platform ios|android --device <id>`で選択sessionにnative端末を明示的に紐付ける。iOSはSimulator UUID、Androidはエミュレータserialを受け付ける。`connect <uri>`の前後どちらでもbindできるが、利用者が宣言した対応であり、VMとrunnerが同じアプリを対象とする証明ではない。再bindで両観測と承認待ち要求を失効する。VMなしでも利用でき、close/idle終了で外部管理の端末・runnerを停止しない。`native`コマンドとMCP native profile/toolsは廃止し、core MCPのsession_bind、snapshot、tap、swipeに統合する。

`snapshot`は端末未登録ならFlutterのみ、VMなしならnativeのみ、bindとconnectの両方があれば両方を観測する。`--source flutter|native|all`で明示選択できる。公開snapshotは毎回両方の前回観測を置換する。混在結果はelements、公開generation、各行のsource/coordinateSpace、取得元別status/limitationを持つ。短い出力でもmodalを確認しやすいようnative行を先に出し、両取得元とも未公開refは使えない。要求した取得が両方成功してから公開し、失敗時は両方の観測を失効する。nativeの空/rootのみはlimitedであり、画面が空だという保証ではない。取得元をまたぐ同時性は保証せず、重複要素は統合しない。nativeのinteractive/depth/key filterは非対応で、compactと完全一致text/identifier/type filterに対応する。

通常の`tap`と`swipe`がFlutterの`@eN`とnativeの`@nN`を受け付ける。取得元はsessionのref登録情報で決まり、上書きできない。nativeのselector・座標には`--source native`を指定し、指定なしのselector・座標は従来のFlutterの意味を維持する。native tapはref、完全一致text/identifier/type selector、x/yのいずれか1つを受け付ける。native ref/selector操作はboundsを含む正規化要素全体を再観測・照合する。refが0件ならSTALE_REF、selectorが0件ならTARGET_NOT_FOUND、複数ならAMBIGUOUS_TARGET、無効bounds/disabledならUNRESOLVABLE_TARGET。同一内容の重複要素とアプリrootにはrefを出さない。自動再送・別取得元への切替は行わず、fill等の未対応native操作は入力前に拒否する。

native座標はiOSがscreen_points、Androidがscreen_pixels。明示座標swipeは--start-x/--start-y/--end-x/--end-yを使う。ref/selector swipeは観測矩形の中心を始点に指定方向へ--distance（既定200、取得元の座標単位）だけ動かす。端点は有限・非負・相互に異なり10,000,000以下で、暗黙のclampや座標fallbackは行わない。明示座標入力はアクセシビリティ取得を要求しない。iOSはplatform既定のdrag速度、Androidは整数丸めと60 swipe stepsを使う。scale・回転は呼出側が考慮する。

session queueと共通device queueで、同daemon内の紐付け済みFlutter/nativeコマンドを直列化する。native入力は同端末のnative refsとdaemon全体のFlutter refsを失効する。宣言されたVM/device対応を証明とみなさないためである。Flutter入力は自sessionの両refと同端末に紐付く別sessionのrefsを失効する。既知のiOS Alert/Android permission-controller観測があればFlutter refを抑止し、入力前にも拒否する。それ以外の遮蔽はunknown。native入力にはtap（clickはtapの別名）またはswipeに加えnative policyを適用し、通常コマンド経由でもnative deny/confirmを迂回できない。snapshotは読み取り扱い。bind変更で承認待ちを失効する。batchも共通router/policyを使う。workflow v1の操作selectorはFlutter限定のままだがfinalSnapshotには両方を含められる。get/is/find/wait/diffは従来のFlutter限定の意味を維持する。出力制限・未信頼content boundariesは両取得元へ適用する。送信後の失敗/timeoutはunknownで、自動再送しない。

daemonは`MARIONETTE_AGENT_NATIVE_RUNNERS`を最大64 KiBのJSONファイルのpathとして読む。形式は`{ "ios": { "UUID": { "port": 18741, "token": "..." } }, "android": { "SERIAL": { "port": 18742, "token": "..." } } }`とし、portは1〜65535の整数、tokenは`[A-Za-z0-9_-]`に一致する32〜128文字だけを許可する。接続先はIPv4 loopbackに固定し、remote hostは設定できない。端末設定の欠落はUNSUPPORTED_CAPABILITY、設定読取・接続失敗はIO_ERROR、不正wire dataはBACKEND_ERROR、期限超過はTIMEOUTとする。診断にtoken・画面文言・runnerの例外詳細を出力しない。

wire protocolはTCP接続ごとに有界のJSON 1行と応答1件を使う。要求にはversion=1・platform・device・token・元のUnix-millisecond deadline・action・必要な座標を含める。両runnerはidentity/tokenを認証し、OS呼出前に期限を確認する。応答にはversion/platform/device/okとsnapshotのelementsまたは汎用error codeを含め、clientは応答のidentityを検証する。要求は16 KiB、観測は10,000要素、応答は8 MiBまでとする。timeoutはclient socketを閉じるが、開始済みOS操作は完了し得るため結果はunknownのままとする。runnerは外部所有で、要求を直列化する。iOSの端末identityはSIMULATOR_UDID、Androidはinstrumentation起動時に転送先の明示serialを渡す。

native操作経路にはidb・adb・xcrun・subprocess・XML dumpの実装を持たない。iOS platform packageにXCUITest bundle、Androidに独立したUI Automator instrumentation APK projectを置く。インストール・テストrunner起動・Androidのport転送は明示的な準備手順とする。既存のdevice/application/recording機能はそれぞれの実装を維持する。iOS実機・任意shell実行・一括権限付与・native文字入力・永続native IDは契約外。準備と観測ループは[ネイティブUIガイド](https://r0227n.github.io/marionette_agent/ja/guides/native-ui/)を参照。


<a id="native-macos-screenshots"></a>
## macOSネイティブスクリーンショット（Issue #58）

`screenshot --source macos --display <1-999> [path]` はFlutter接続なしで有効な画面全体を選択する。sourceの既定値は `ios-simulator`。Flutter撮影・crop・注釈は廃止されたままとし、CLI・MCP・workflowは共通handlerを使う。失敗時のfallbackは行わない。

macOSは同梱の独立したXCTest UI-test runnerをXcodeでビルドし、`XCUIScreen.screens[index - 1].screenshot()`を`XCTAttachment`として保存します。`xcresulttool export attachments`でPNGを回収します。旧screencapture静止画経路は削除しました。macOS 13以降・ログイン済みWindowServer・full Xcodeが必要です。runnerはローカルad-hoc署名を使い、開発者証明書は不要です。初回のビルド・起動も同じ絶対deadlineに含むため `--timeout 120000` を推奨します。ビルド結果はdaemon内で再利用し、要求を直列化し、終了時に所有runnerとbuild/stagingを回収します。

`device list --platform macos`は現在のactive display順序、CoreGraphics ID・geometryを返します。index 1はmain displayで、番号は現在の順番であり永続的なhardware識別子ではありません。毎回明示的に選択します。撮影前後のID・順序・geometry・mode・rotationを比較し、変化したら`TARGET_NOT_FOUND`として画像を破棄します。別displayへの切替は行いません。XCTestとの間はatomicではないため撮影中にdisplay構成を変更しないでください。hardware mirrorは描画元のprimaryを公開します。標準panel・menu・権限UIは別window/processの場合があるためwindow単体の撮影は提供しません。 公開XCTest APIはmainが先頭の配列のみでdisplay IDを公開しません。3画面以上の構成ではmain以外をUNSUPPORTED_CAPABILITYとして拒否し、CoreGraphics IDを推測しません。main画面と2画面構成の両画面を対象とします。

選択displayの見えている内容全体を取得し、**他アプリも含みます**。対象displayで現在表示中のSpace・全画面Spaceのみです。移動したアプリには追従せず、別displayへ移動したアプリは写りません。遮蔽物は写り、最小化・非表示window、別Space・displayのUIは写りません。保護UI・secure contentはOSにより除外される場合があります。dialogを閉じる、Spaceを切り替える、windowを前面へ出す、保護UIを回避する操作は行いません。アプリ終了後もdisplayは存在し、Flutter接続なしで撮影できます。対象displayの切断は対象消失です。

成功時は`paths`に加え`capture:{source:"macos-xcuiscreen",method:"xcuiscreen",scope:"display",displayIndex,displayId,pixelWidth,pixelHeight,bounds:{x,y,width,height,unit:"macos_global_points"},scaleX,scaleY,includesOtherApplications:true}`を返します。pixel寸法はPNG実データから読み共通decoderで検証します。scaleは取得pixel寸法÷display boundsでRetinaも含みます。Flutter座標ではありません。text出力にも同じmetadataを含めます。nativeと注釈やref/selector cropの併用は撮影前に拒否します。`diff screenshot`は既存のiOS/Android device撮影契約を使います。

[CGPreflightScreenCaptureAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())を権限要求なしに呼びます。falseは`SCREEN_CAPTURE_PERMISSION_REQUIRED` / exit 1 / `not_sent`で、対象消失・変更（`TARGET_NOT_FOUND` / exit 4）、timeout（exit 5）、取得失敗（`IO_ERROR` / exit 1）と区別します。公開preflightはBooleanしか返さないため、**一度も要求していない状態と明示的拒否は区別できません**。TCC状態を推測せず両者を含む旨を返します。daemon実行元のterminal/host appに画面収録権限が必要です。TCC database読取り、権限要求API、OS設定変更は行いません。Web録画も同じread-only probeを再利用し、従来の`IO_ERROR`契約を維持します。

native取得は私有一時領域を使い、子processのstdout/stderrを破棄します。timeout時は子processを停止・回収してからcleanupし、遅れた成功を公開しません。PNGを共通writerへ渡し、PNG/JPEG変換・排他的保存・その要求の失敗時rollbackを再利用します。元の絶対deadlineにnative取得・IPC・保存を含みます。40 MiB超はbase64転送前に拒否します。path/directoryの優先順位と命名規則は維持します。
