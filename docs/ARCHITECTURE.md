# marionette_agent — アーキテクチャ

本書は[SPEC.md](SPEC.md)の`marionette_agent 0.0.1`契約を実現する現行構成を定義する。単独コマンドとworkflow v1は実装済み。コマンド追加時の具体的な不変条件は[実装契約](ja/command-contract.ja.md)を参照する。

## 構成

```text
AI Agent / Shell
  → Dart CLI（解析・workflow読込／検証・出力・ファイル保存）
  → Unix domain socket（実行要求だけを送るローカルIPC）
  → Dart daemon（session・直列実行・workflow・snapshot/ref）
  → Marionette adapter（VmServiceConnector）
  → Dart VM Service WebSocket
  → marionette_flutter（iOS Simulator内のFlutterアプリ）
```

1ユーザー・1ランタイムディレクトリに1daemonを置く。daemonはsessionごとに独立したconnectorとキューを所有する。CLIとdaemonはDartで実装し、MCPプロセスは介在しない。

### ディレクトリ

```text
packages/marionette_agent/
  bin/marionette_agent.dart
  lib/src/
    cli/        # parser、text/JSON renderer、artifact writer
    diagnostics/# loggingレコードの秘匿化、request単位の収集、stderr出力
    protocol/   # versioned request/response、error、DTO
    daemon/     # 起動、socket server、dispatch、期限と直列化
    session/    # lifecycle、接続所有権
    snapshot/   # 正規化、ref、対象の事前検証
    backend/    # Backend interface、Marionette adapter
    commands/   # 共通サービスを使う各操作
    workflow/   # schema、model、親/step実行制御
  docs/         # 実装契約、workflow v1仕様
  examples/     # JSON／YAML workflowとinputs例
  test/         # 単体・IPC・契約テスト
  integration_test/ # SimulatorでのCLIシナリオ
```

protocolはDartの値とJSONだけを扱う。コマンド層はBackend interfaceに依存し、上流connectorやresponse mapを直接扱わない。rendererはbackend例外を解釈しない。

## Marionette adapter

`package:marionette_mcp/src/vm_service/vm_service_connector.dart` のVmServiceConnectorを再利用する。内部API依存はadapterに限定する。pubの `marionette_mcp: 0.6.0` を完全固定し、lockfileも管理する。固定版connectorとbindingのresponse fixtureを契約テストで検証する。

隣の `../marionette_mcp` は参考ソースであり、pubの解決済みバージョンと一致するとは限らない。固定版は構造化statusで成功を返し、swipeの両方式を提供する。identifier matcherは未対応のためUNSUPPORTED_CAPABILITYを返す。配布時に隣接リポジトリへのpath依存を要求しない。

| ローカル操作 | 上流呼び出し |
| --- | --- |
| connect / close | connect / disconnect |
| snapshot | getInteractiveElements |
| tap | tap |
| fill | enterText |
| swipe / 初版scroll | swipe |
| screenshot | takeScreenshots |
| logs | getLogs |

adapterはURI正規化、wire変換、response検証、例外分類を担当する。HTTP→WS、HTTPS→WSSへ変換するとき認証path/queryを保持し、`/ws` を重複追加しない。機能不足はUNSUPPORTED_CAPABILITY。成功メッセージ文字列だけで成否を判定しない。

Backend interfaceはconnect、disconnect、inspect、tap、fill、swipe、captureScreenshots、readLogsを型付き引数・結果で提供する。上流mapは境界で閉じる。scrollは同じswipe primitiveを使い、helpと出力はscrollとして返す。

## IPCとdaemon起動

CLIは要求1件を送り、最終応答1件を受けて終了する。IPCは改行区切りJSON。要求はprotocolVersion、requestId、session、command、params、deadlineを持つ。応答はrequestId、request内で発生した秘匿済みdiagnostics、SPECの結果包絡を持つ。detached daemonの`logging`レコードはrequestのZoneごとに収集して呼出元CLIで再発行し、stderrへ出力する。INFO未満、認証URI、添付error、stack traceは転送しない。CLIのJSON schemaとIPC protocolのバージョンは独立させる。

ランタイムディレクトリはユーザー専用・権限0700。socketと起動情報も他ユーザーから読めない権限にする。macOSのsocketパス長に収まる短いパスを生成する。起動情報にはPID・protocolVersion・起動識別子を含め、VM Service URIは永続化しない。

OSの排他ロックで起動を直列化し、取得後に稼働daemonを再確認する。CLIの実行形態（Dartソース／コンパイル済み）に応じて同じプログラムを内部daemonモードで起動する。handshake完了を待ち、バージョン不一致は説明可能なエラーにする。

古いsocketは生存確認とロックのもとで回収し、PIDだけを根拠に別プロセスをkillしない。最後のcloseと新規connectは管理キューで直列化する。終了中へのconnectは送信前なら再接続できるが、送信後のUI操作は再送しない。

IPCのサイズ上限は初版で1フレーム64MiB。画像はbase64としてdaemonからCLIへ返し、超過は明示エラー。screenshotのファイル保存は呼出元CLIが担い、相対パスは呼出元のcwdで解決する。recordは例外としてutilがdaemon内で保存し、CLIは絶対pathを渡す。

応答配送の期限は要求deadline+250msとし、受信しないクライアントのsocketも切断する。最後のclose後も配送・切断を無期限に待たず、250msの猶予で残るクライアントを破棄してdaemonの寿命ロックを解放する。最終応答の送信開始後は別のエラーフレームを追加しない。

## sessionと実行順序

sessionはconnecting→connected→disconnected、closeで破棄。接続失敗時はconnectorをdisposeする。名前、正規化URI、connector、接続世代、snapshot、実行キューを所有する。daemon全体でref採番とURI所有権を管理する。

同一sessionの観測・検証・操作は1つのキュー上で実行し、異なるsessionには別キューを使う。受付時と実行前に期限を確認し、期限切れの未送信要求は実行しない。

UI操作は、引数・session確認→対象解決と再観測→ref失効→バックエンドへ1回送信→結果返却の順。成功dataにはrequiresSnapshot: trueを含める。

送信後の通信断・timeoutはoutcome: unknown。connectorを破棄しdisconnectedにする。Dart Futureのtimeoutだけでは上流処理が取り消されないため、接続世代を照合し、遅延応答が新しい状態を書き換えないようにする。

## snapshotとref解決

SnapshotServiceは要素情報を正規化し、RefStoreはref→観測世代・selector・要素属性を保持する。key、identifier、対応確認済みtext、typeの順で一意な候補を選ぶ。公開snapshotと内部の事前観測は分離し、事前検証が新しいrefを発行しないようにする。

公開snapshotはselectorごとの一致数を先に集計する線形処理とし、256要素ごとに期限・接続世代を確認してイベントループへ制御を戻す。固定bindingのtextは既知の5型だけを照合可能とする。未知の型はSemantics派生型と区別できないため表示だけに使い、key/typeで操作する。不正な観測objectはadapter内でBACKEND_ERRORへ分類する。

ElementInfo.valueは信頼できるselector候補、candidateValueは衝突し得る観測値を返す。textの重複集計・再観測・waitにはcandidateValueを使って未知の型も数え、単独の由来未確認textはUNRESOLVABLE_TARGETとする。

Marionetteの要素一覧は完全なツリーではなく、Semanticsの表示用textがTextMatcherに対応しない場合がある。配列添字をselectorにせず、対象を確定できなければ読み取り情報と理由を返す。上流は最初の一致を選ぶため、契約テストには重複・Semanticsラッパー・非表示要素を含める。

事前観測では原子的な対象保証にならない制約はSPECに従う。アプリ側への永続ID拡張追加は初版に持ち込まない。

## コマンド拡張境界

通常のアプリ操作コマンドはCLI parserとdaemonのCommandRegistryへ同じコマンド名を登録する。recordはVM Service非依存のためSessionManagerの共通session queueでRecordServiceへ分岐する。handlerはIPC paramsを信頼せず、未知field、型、必須・排他条件をmutation開始前に再検証する。ref／selectorと有限数の共通検証は`commands/arguments.dart`へ集約する。

CommandContextにsession実行、対象解決、期限確認、ref失効、mutationの1回送信を集約する。handlerは独自のqueue、retry、session生成、ref保存、接続破棄を実装しない。共有型は`lib/marionette_agent.dart`から公開し、上流connectorやresponse mapをコマンド層へ漏らさない。

workflowはSessionManagerで通常経路から分岐するが、各stepは既存CommandRegistryと新しいExecution／CommandContextを使う。1つのExecutionで複数mutationを送信したり、stepからSessionManagerを再帰呼び出ししたりしない。

waitは単独コマンドとworkflow stepの両方を同じCommandRegistry handlerへ正規化する。handlerはselector、state、poll間隔を再検証し、CommandContext.read経由でinspectだけを直列pollする。公開snapshot／refを生成せず、mutation経路と自動retryを持たない。workflowはstep固有期限を子Executionへ設定してから同じhandlerを呼び出す。

## 検証

- 単体: 引数の排他・有限値、JSONと終了コード、ref失効・曖昧性・session分離、workflow parse／binding／実行。
- adapter契約: 固定依存のresponse fixtureとFakeBackendでマッピング・異常系を確認。
- IPC: 別CLIプロセス間の保持、同時起動、並行session、close競合、daemon停止、waitの共通期限、送信前後のtimeout。
- Simulator: `example/`を使い、独立した2アプリ、入力欄、PageView、Dismissible、スクロール領域、ログ、単独waitの出現・消失、workflowの停止と最終snapshotを検証。

FakeBackendの合格はSimulator検証の代わりにしない。コード変更時はパッケージ内でformat、analyze、関連testを実行し、引き継ぎ時は全体testも実行する。Simulator検証にはFlutter／bindingバージョン、Simulator機種・OS、コマンド、観測結果を記録する。

## 実装で利用する既存機能

引数解析・usageはargs、属性比較はcollection、パス構築はpath、PNG復号検証とJPEG変換はimage、RPCエラー定義はvm_serviceを使う。IPCはdart:ioのUnix socketとOSファイルロック、dart:convertのUTF-8/LineSplitter/JSONを利用する。独自処理はsession寿命、ref検証、期限・送信結果の契約、フレーム上限など製品固有の部分に限定する。

上流connectorのisConnectedだけでは通信断を検知できないため、状態照会と1秒間隔のhealth probeをsessionキュー上で実行する。CLIの要求期限後はdaemonのTIMEOUT応答を届けるため最大250msのIPC猶予を設けるが、backend実行期限は延長しない。

## Workflow v1

[workflow仕様](ja/workflow-file-spec.ja.md)に従い、CLIのWorkflowLoaderが期限付きでJSON／YAMLを読み、閉じた同梱schemaとWorkflowPlanで全step・input bindingを検証する。`yaml 3.1.4`を完全固定し、内部scanner依存をloaderだけへ隔離する。token段階でtag／anchor／aliasと深さを拒否し、JSONの重複keyは構造scanで検出する。schemaはDart定数として同梱し、コンパイル済みCLIでも外部fileやnetworkを必要としない。`workflow schema`と`workflow validate`はRuntimeDirectoryもdaemonも作成しない。

SessionManagerはworkflowを単独Execution.boundの外で分岐し、WorkflowExecutionが1つのqueue entry・開始epoch・全体deadline・停止状態・進捗・snapshot候補を所有する。各stepは親へ固定された新しいExecutionを持ち、従来の1回送信ガードを維持する。親はstepで確定したoutcomeを再分類しない。timeout時は親を停止し、開始epochだけを破棄する。遅延Futureは親停止状態を確認するため、新しい接続・ref・後続stepを変更できない。

wait stepは単独waitと同じ登録済みread handlerを使い、ElementInfo.candidateValueによる一致をinspectでpollし、単独のtext候補は由来の信頼性も確認する。CommandContext.checkで計算後の期限も確認し、公開refを生成しない。全stepが既存CommandRegistryを直接呼び、SessionManagerへstep単位で再帰しない。最終snapshot候補は後続mutationで破棄し、失敗時は返さない。

IPC protocolVersionは4（共通出力policyとidle設定handshake追加）。requestのparamsはworkflow templateとinputs objectのみで、daemonでも全件検証してから接続・selector capabilityを確認する。AgentError.detailsはIPCとwithOutcomeで保持する。配送失敗はunknown/progressKnown:falseにし、UIを再送しない。schema/validateはRuntimeDirectory.prepareを呼ばない。

workflow応答のframe生成・配送失敗はdaemonのfallbackでもunknown/progressKnown:falseとsession名を保持する。CLIのローカル検証はparseと意味検証後も絶対deadlineを確認し、期限を過ぎた成功を返さない。

## ScreenshotのCLI側変換（Issue #13）

`cli/common_options.dart`が形式・品質のroot登録、既定PNG／JPEG品質90、値検証と拡張子規則を所有する。`CliParser`はscreenshotのpathを接続前に検証し、拡張子省略時に選択形式の拡張子を付加する。help/versionと全サブコマンドも共通定義を継承する。形式・品質はInvocationのCommonOptionsからrunnerへ渡し、IPC paramsやbackend adapterへ追加しない。workflow内のscreenshot対応やprotocolVersion変更は行わない。

`cli/artifact_writer.dart`はbackendのPNGを全件復号検証し、PNGなら元のバイト列、JPEGなら白背景へ合成した8-bit RGBを固定image 4.9.1のJpegEncoderへ渡す。RGBA／grayscale alpha／palette／16-bitを画素の正規化値で処理し、透過を捨てる前に合成する。encoderに透過の合成を任せないため、JPEG端部のpaddingによる反復合成も避ける。品質0はencoderの最低品質1へ丸められる。imageの内部importは従来のPNG decoderと同じ境界へ集約し、依存更新時は画像fixtureを再検証する。

runnerはCLI開始時の共通絶対deadlineをそのままwriterへ渡す。復号・合成・encode後にも期限を確認してから、従来の全宛先の排他的予約と書込みへ進む。同期codec自体は中断しないが、遅れて得た画像を成功として公開しない。予約後の失敗・TIMEOUTではこの要求の予約file・書込み済みfile・自動directoryを回収する。OSによるcleanup失敗時は残存し得るが、成功pathsを返さず元のエラーを保持する。テストの時計注入により変換後・予約後・書込み後の期限切れをhost負荷によらず検証する。

## 入出力の安全境界

- 画像保存は全宛先をDartの排他的ファイル作成で予約してから書き込む。既存ファイル・ディレクトリ・symlinkを上書きせず、途中失敗時はこの要求で作成したファイルを削除する。予約後に別プロセスが保存先を意図的に差し替える競合までは保証しない。
- workflowのpath入力は通常ファイルに限定し、FIFO等は開く前に引数エラーにする。ストリーム入力は期限付きstdin (`-`)を使う。
- diagnosticsのZoneには終了可能なcollectorを入れ、要求完了時にListへの参照を外す。接続時に登録したlistenerの後発ログは通常のstderr経路へ戻す。
- ref/selectorの排他・型・空文字と有限数の検証は`commands/arguments.dart`へ集約し、CLIのtarget parserとdaemonの操作handlerで共有する。
- 通常コマンドを含む全エラーのテキスト出力にoutcomeを表示し、workflowには進捗既知性、完了step数、失敗stepも付加する。daemonは要求処理開始後の応答生成失敗をunknownへ分類する。

## 内部プラットフォームサービス

`packages/marionette_agent_util`は録画専用ではなく、marionette_agentで必要になるOS／端末別処理を集約する内部パッケージ。CLI/session/protocolやmarionette_mcpへの逆依存を持たない。今後の端末情報等も独立したサービスとして追加する。

```text
CLI parser → RecordService（共通引数検証・エラー変換）
            → RecordingManager（owner・端末排他・保存・終了）
              → ScreenRecorder / RecordingHandle
                → iOS: simctl / Android: adb / macOS: screencapture
```

CLIは同一repo内の`../marionette_agent_util`へpath依存し、両パッケージはpublish_to:noneとする。配布は両パッケージを含むcheckoutからの起動またはCLIのコンパイル済みバイナリを使用する。隣接する参考リポジトリへのpath依存は導入しない。

record startとconnectだけがdaemonを自動起動できる。sessionは録画だけでも予約・保持でき、後からVM Serviceを接続できる。recordのstart/stop/statusとcloseは既存session queueで直列化し、長時間のフレーム処理はqueue外で継続する。録画にはUI mutationのExecution.boundを使わず、utilが開始期限・停止後の有界cleanup・状態を管理する。VM Serviceのepoch破棄は録画へ波及しない。

RecordingManagerは開始前にdeviceを予約し、backendの開始確認後に返す。startのbackend待ちは要求期限と30秒上限で打ち切り、遅れて生成されたhandleの停止・予約回収は追跡付きcleanupとして継続する。start時の終了競合や停止失敗でも、handleの終了確認まではdevice予約を解放しない。stopの要求期限超過後も終了処理を保持し、終わるまで同じdeviceへ別録画を開始しない。Androidの自動終了も同じfinalizationへ合流する。closeでは録画を確定してから所有権を解放する。daemonのSIGINT/SIGTERMではRecordingManager.disposeが開始待ち・停止・保存・追跡cleanup全体を60秒に制限する。期限超過時はRecordingHandle.abortで所有プロセスを強制停止し、ファイル読込をキャンセルして出力を閉じる（追加待ちは最大5秒）。stagingと未確定の予約先を保持し、遅延完了で動画を公開しない。Androidは固有remote pathとPIDを照合して強制停止を試みるが、端末切断時の成功は保証しない。OSで進行中のI/Oは取り消しを保証できないため削除と競合させない。

出力先予約、private staging、iOSのSIGINT、Androidの固有remote file名とcmdline照合付きPIDへのSIGINT、adb pull、macOSの起動生存確認・停止はutil内に閉じ込める。CLIのstdoutへ子プロセスの出力を流さず、失敗はPlatformException→AgentErrorへ変換する。未対応web/linux/windowsもutilでthrowし、CLI parserとdaemonの両方で共通検証する。

単体テストは保存保護・端末排他・開始失敗・停止期限・異常終了・終了競合、CLIテストは未接続録画session・ref保持・通信断後の継続・close・未対応platformを検証する。`integration_test/record_smoke.dart`は製品CLIで開始→接続→操作→動画確定→重複stop→上書き拒否→close確定を確認する。実動画を復号して画面変化を確認する。

## 共通安全オプション（Issue #2）

`cli/common_options.dart`が既存・新規の全共通オプションの名前、help、既定値、ArgParser登録、重複検出、構文エラー回復、値検証とCommonOptionsを所有する。CliParserはrootへ一度登録し、argsの継承によって全command／subcommandへ適用する。個別command parserに定義を複写しない。IPCのsessionと出力上限の再検証も同じ値検証へ委譲する。

Requestは`maxOutput`と`outputJson`をparams外に持つ。`output/content.dart`の項目serializerをdaemonの制限とCLIの表示が共有し、code point予算を一致させる。SessionManagerはqueue内で公開snapshotを完成させた後に制限し、SnapshotService.retainPublishedで返却generationの省略refを削除してからqueueを解放する。workflow finalSnapshotもこの経路を通る。未公開refを後続要求から利用できる時間窓を作らない。nonceはrendererだけがCLI呼出しごとに生成し、JSONでは対象dataにmetadataとして付加する。

DaemonClientは起動時idle値を内部daemon引数で渡す。既定値・内部引数の検証もCommonOptionsを利用する。handshakeとprivate metadataは確定したidleTimeoutMsを含み、clientは明示値との不一致を要求送信前に拒否する。起動lock取得後の再openでも同じ照合を行う。省略時に既存値を上書きせず、設定のためだけのdaemon再起動も行わない。

DaemonServerはclient受信／配送とSessionManagerのpendingを監視し、全queueが空になってからidle timerを開始する。期限切れqueue entryも実際にdrainするまでpendingから除かない。queue完了通知はhealth probe後のtimer未設定を回復するが、既存のidle intervalは延長しない。health probe実行中の期限到達は完了まで延期する。timerは通常のcloseへ合流するため、record確定・全session破棄・socket削除・寿命lock解放を共有する。
