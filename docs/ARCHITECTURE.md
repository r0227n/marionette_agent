# marionette_agent — アーキテクチャ

## doctor境界 (Issue #9)

`cli/runner.dart`はdoctorを`RuntimeDirectory.prepare`より前にローカル配送する。
`cli/doctor.dart`がhost/runtimeのread-only検査、固定依存の宣言/lock比較、Simulator列挙、
check状態と終了コード集計を所有する。外部processとprobeはfixtureへ差し替え可能。
daemon socketは所有者/0700確認後に接続し、既存protocol decoderでhandshakeだけを読む。
DaemonClient、SessionManager、runtime準備、command dispatchを呼ばない。
DaemonServerはhandshakeだけのclientが切断した時に元のidle期限を再利用する。
要求をdispatchした場合だけ新しい無操作区間を開始し、doctorによる寿命の延長を防ぐ。

`backend/doctor_probe.dart`は公開vm_service APIで独立clientを作り、既存backendのURI正規化を再利用する。
上流internal APIのimportを追加せず、観測したextension登録とbinding versionだけを返す。
URI・remote error本文を境界の外へ返さない。finallyと遅延完了handlerで接続を解放する。
各process/RPCは全体deadlineの残り時間を使い、IPCには最大1秒の上限も設ける。
診断結果は共通Resultのdataに入れ、runnerがdoctorのdata.exitCodeをprocess終了値に適用する。
text rendererはcheck状態/理由/次手順/details、JSONは共通envelopeを表示する。

本書は[SPEC.md](SPEC.md)の`marionette_agent 0.0.1`契約を実現する現行構成を定義する。単独コマンドとworkflow v1は実装済み。コマンド追加時の具体的な不変条件は[実装契約](ja/command-contract.ja.md)を参照する。

## 構成

`is visible`は`CommandContext.observeTarget`から`SnapshotService.observeTarget`を利用し、sessionのread境界でinspectする。操作用resolveと対象再観測・一意性・stale判定を共有し、操作用resolveのみ非表示を拒否する。コマンドはnullableなvisibleをknown/valueへ変換するだけで、mutationや公開snapshot/ref更新を行わない。単体およびIPC fixtureでtrue/false/nullと対象解決エラーを検証する。

```text
AI Agent / Shell
  → Dart CLI（解析・workflow読込／検証・出力・ファイル保存）
  → Unix domain socket（実行要求だけを送るローカルIPC）
  → Dart daemon（session・直列実行・workflow・snapshot/ref）
  → Marionette adapter（VmServiceConnector）
  → Dart VM Service WebSocket
  → marionette_flutter（iOS Simulator内のFlutterアプリ）
```

1ユーザー・1ランタイムディレクトリに1daemonを置く。daemonはsessionごとに独立したconnectorとキューを所有する。CLIとdaemonはDartで実装する。MCPクライアントは任意のstdio MCPプロセスを通じて同じCLIを呼び出す。

### MCP境界

`cli/commands/mcp.dart`が起動引数を解析し、runnerがpolicy読込・runtime作成より前に`mcp/server.dart`へ配送する。`dart_mcp`のMCPServer＋ToolsSupportとstdioChannelがJSON-RPC、初期化、version交渉、通信終了を所有する。serverは固定profileの登録、pagination、入力の秘匿化、CLI結果のCallToolResult変換、保存済み画像のImageContent化を担当する。MCP通信のprotocol log sinkは設定しない。

`mcp/catalog.dart`は型付きschemaと固定コマンド／argvの対応を所有する。値付きoptionは`--name=value`、位置引数は`--`以降へ配置し、入力文字列をCLI optionやshell構文として解釈しない。自由なargv入力は提供しない。業務上の対象解決・操作条件はCLI parserと既存commandへ委譲する。

`mcp/executor.dart`は既存の起動形態判定を再利用し、source／snapshot／compiledの同じCLIを通常processとして1回起動する。stdinを閉じ、stdoutを有界に取得し、stderrをdrainして破棄する。CLI終了値と検証済みResult包絡をserverへ返す。timeout・MCP終了では所有するCLI processだけを回収する。daemonやアプリの所有権は既存session層に残るため、EOFで他のCLI sessionを閉じない。

依存方向はMCP → CLI／IPCであり、backend／session／commandsからMCP SDKへ依存しない。`test/mcp_test.dart`はSDKクライアントと製品stdio process、fixture daemonを接続し、`integration_test/mcp_smoke.dart`は同じ経路でSimulatorのexampleを操作する。契約は[SPEC](SPEC.md#stdio-mcpサーバー)を参照する。

### ディレクトリ

```text
packages/marionette_agent/
  bin/marionette_agent.dart
  skills/       # 外部発見用のhidden stub
  skill-data/   # core・simulator-verifyの実行時ガイドと補助ファイル
  lib/src/
    mcp/        # dart_mcp stdio server、typed tool catalog、CLI process実行
    cli/        # 呼出元の解析・出力・ファイル/process処理
      commands/ # catalogとコマンド別のArgParser構文
      command.dart # CliCommand型。parserには依存しない
      parser.dart  # config/環境/CLIの優先順位とInvocation生成
      help.dart    # usageテキスト
    diagnostics/# loggingレコードの秘匿化、request単位の収集、stderr出力
    protocol/   # versioned request/response、error、DTO
    daemon/     # 起動、socket server、dispatch、期限と直列化
    session/    # lifecycle、接続所有権
    snapshot/   # target.dartの対象型、ref、対象の事前検証
    backend/    # Backend interface、Marionette adapter
    commands/   # 共通サービスを使う各操作
    workflow/   # schema、model、親/step実行制御
  docs/verification/ # 実環境の検証記録（仕様・実装契約はroot docs/）
  examples/     # JSON／YAML workflowとinputs例
  test/         # 単体・IPC・契約テスト
    support/    # FakeBackend、入力保持fake、共通Request fixture
  integration_test/ # SimulatorでのCLIシナリオ
```

protocolはDartの値とJSONだけを扱い、CLIやargsには依存しない。commands以下はIPC paramsの検証・型付き要求・handlerを所有する。CLIの構文は同じ検証を呼ぶが、handlerからCLIへ依存を戻さない。内部は必要な定義を直接importし、公開barrel経由の循環依存を作らない。`architecture_test.dart`でdaemon各層からCLI/args/公開barrelへの依存を拒否する。

コマンド層はBackend interfaceに依存し、上流connectorやresponse mapを直接扱わない。URIの正規化・秘匿化は`backend/connection_uri.dart`に置き、sessionやstate保存が具体adapterをimportせずに使う。FakeBackendは`test/support/`だけに配置し、製品の公開exportには含めない。rendererはbackend例外を解釈しない。

ローカル実行は`batch_loader.dart`、`connection_state.dart`、`installer.dart`、`observation_diff.dart`へ分ける。共通の通常ファイル読込は`input_file.dart`、期限付きprocess実行は`process_runner.dart`が所有し、state/policy/batchが画像差分やdoctorの実装を読み込む必要をなくす。

## Skill配信のローカル境界

`cli/commands/skills.dart`がskillsの文法、`cli/help.dart`がhelp、`cli/skill_catalog.dart`がpackage/環境変数からの探索、frontmatter解析、catalogと専用text/JSON出力を所有する。catalogはCLI parserに依存しない。`cli/runner.dart`は引数解析後、policy読込・RuntimeDirectory.prepareより前に実行して返る。成功時も失敗時もIPCへ渡さず、session/refを参照しない。`--debug`は既存診断を使う。

CliParserは最初の構文解析で識別したコマンドをconfig読込より前に呼出元へ通知する。これによりconfigの失敗もskills等の出力契約へ分類できる。frontmatterは独立した開始・終了行を検証してからその区間だけを読み、空のnameはcatalogへ登録しない。

`skills/`の導入用stubと`skill-data/`の実行時ガイドをDartパッケージ内に置く。Dart起動ではIsolate.resolvePackageUri、手動コンパイルでは実行ファイルを基準とする配布rootを使う。`installer.dart`はソースの両ディレクトリを新規bundleへコピーし、相対bundle名をDart環境定数としてコンパイルする。成功したバイナリだけを切り替え、失敗時は新規bundleを回収する。既存版のbundleは保持する。実行時に展開・生成・ダウンロードする経路を持たない。

Skillの互換JSONは`SkillsOutput`の専用境界で生成し、protocolのResult/schemaVersionは変更しない。コマンド詳細、探索優先順位、配布時に同伴するbundleの契約は[SPEC](SPEC.md#同梱skillの配信)を参照。

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
| screenshot --annotate | callCustomExtensionで固定名marionette_agent.captureMappedScreenshotを呼ぶ（opt-in providerが必要） |
| logs | getLogs |

adapterはURI正規化、wire変換、response検証、例外分類を担当する。HTTP→WS、HTTPS→WSSへ変換するとき認証path/queryを保持し、`/ws` を重複追加しない。機能不足はUNSUPPORTED_CAPABILITY。成功メッセージ文字列だけで成否を判定しない。

Backend interfaceはconnect、disconnect、inspect、tap、fill、swipe、captureScreenshots、readLogsを型付き引数・結果で提供する。上流mapは境界で閉じる。scrollは同じswipe primitiveを使い、helpと出力はscrollとして返す。

注釈captureは任意のBackendへ必須メソッドを追加せず、別のMappedScreenshotBackend能力として定義する。MarionetteBackendは固定名provider応答のsupported/status、単一画像、ScreenshotGeometry v1を検証し、MappedScreenshot DTOへ変換する。geometryはversion=1、viewCount=1、空でないviewId、originX=originY=rotation=0、正の整数pixelWidth/pixelHeight、有限で正のlogicalWidth/logicalHeightを要求する。CLIはIPC後にもgeometryと実PNG寸法を照合し、x方向pixelWidth/logicalWidth、y方向pixelHeight/logicalHeightを適用する。向きや倍率を画像またはboundsから推測しない。

固定binding 0.6.0はRenderViewのlayerをFlutterView.physicalSizeへ描画し、maxScreenshotSize設定時にはfloorした寸法へresizeする。失敗viewを画像配列から除くため、配列indexをview IDと見なせない。ElementInfo.boundsはRenderBox.localToGlobal(Offset.zero)とsizeであり、通常応答は対応metadataを含まない。このため通常takeScreenshotsの結果を注釈へ流用しない。example/lib/mapped_screenshot.dartはdebug時にopt-in providerを登録し、単一RenderViewのlayerから未resize画像とそのviewの明示geometryを一緒に返す。capture中のview数・identity・physicalSize・devicePixelRatio変更は非対応として返す。上流パッケージの変更、隣接repoへのpath依存、overlay注入は不要。一般binding対応には同等のcapture metadata契約の上流提供が必要であり、現時点ではexample provider構成だけが実環境検証対象である。

SnapshotService.annotationTargetsは公開済みrefsを再観測して照合する読み取り専用経路である。capture前後に照合し、refを新規発行・失効しない。CLIのscreenshot_annotationは純粋なPNG合成境界で、bounds不備とラベル配置不足を明示的に省略する。artifact_writerが元bytesとは別のPNGを排他的に保存し、同じdeadlineをdecode・合成・encode・保存まで確認する。一般の独自拡張CLIは引き続き対象外で、固定名providerはSPECの限定例外である。

## IPCとdaemon起動

CLIは要求1件を送り、最終応答1件を受けて終了する。IPCは改行区切りJSON。要求はprotocolVersion、requestId、session、command、params、deadlineを持つ。応答はrequestId、request内で発生した秘匿済みdiagnostics、SPECの結果包絡を持つ。detached daemonの`logging`レコードはrequestのZoneごとに収集して呼出元CLIで再発行し、stderrへ出力する。INFO未満、認証URI、添付error、stack traceは転送しない。CLIのJSON schemaとIPC protocolのバージョンは独立させる。

ランタイムディレクトリはユーザー専用・権限0700。socketと起動情報も他ユーザーから読めない権限にする。macOSのsocketパス長に収まる短いパスを生成する。起動情報にはPID・protocolVersion・起動識別子を含め、VM Service URIは永続化しない。

OSの排他ロックで起動を直列化し、取得後に稼働daemonを再確認する。CLIの実行形態（Dartソース／コンパイル済み）に応じて同じプログラムを内部daemonモードで起動する。handshake完了を待ち、バージョン不一致は説明可能なエラーにする。

古いsocketは生存確認とロックのもとで回収し、PIDだけを根拠に別プロセスをkillしない。最後のcloseと新規connectは管理キューで直列化する。終了中へのconnectは送信前なら再接続できるが、送信後のUI操作は再送しない。

IPCのサイズ上限は初版で1フレーム64MiB。画像はbase64としてdaemonからCLIへ返し、超過は明示エラー。screenshotのファイル保存は呼出元CLIが担い、相対パスは呼出元のcwdで解決する。recordは例外としてutilがdaemon内で保存し、CLIは絶対pathを渡す。

`--screenshot-dir`は`cli/common_options.dart`で登録・空文字／NUL検証し、`CommonOptions.screenshotDir`からrunner経由で`cli/artifact_writer.dart`へ渡す。IPC paramsやdaemon設定には追加しない。writerが明示path > directory > 一時保存を選び、pathがある場合はdirectoryへ触れない。directoryは事前作成済みの実directoryに限定し、自動作成やdirectory自身のsymlink追跡はしない（祖先のsymlinkは許可）。相対指定は呼出元cwdで正規化し、返却pathを絶対化する。

directory指定では直下に128bitの`Random.secure`のhexを含むPNG名を要求ごとに生成する。既存の複数画像の連番化・全画像検証・全宛先の排他的予約・書込み・失敗時cleanupを共用する。生成名の衝突も既存pathとしてIO_ERRORにし、上書きや再撮影をしない。指定directoryはcleanup対象に含めない。未指定時の一意な一時directoryと`screen.png`は維持する。受入検証は`screenshot_directory_test.dart`で競合・保存失敗、`screenshot_cli_test.dart`で製品CLIのtext/JSONとcwd・呼出し間の設定分離を確認する。

応答配送の期限は要求deadline+250msとし、受信しないクライアントのsocketも切断する。最後のclose後も配送・切断を無期限に待たず、250msの猶予で残るクライアントを破棄してdaemonの寿命ロックを解放する。最終応答の送信開始後は別のエラーフレームを追加しない。

## sessionと実行順序

sessionはconnecting→connected→disconnected、closeで破棄。接続失敗時はconnectorをdisposeする。名前、正規化URI、connector、接続世代、snapshot、実行キューを所有する。daemon全体でref採番とURI所有権を管理する。

同一sessionの観測・検証・操作は1つのキュー上で実行し、異なるsessionには別キューを使う。受付時と実行前に期限を確認し、期限切れの未送信要求は実行しない。

UI操作は、引数・session確認→対象解決と再観測→ref失効→バックエンドへ1回送信→結果返却の順。成功dataにはrequiresSnapshot: trueを含める。

送信後の通信断・timeoutはoutcome: unknown。connectorを破棄しdisconnectedにする。Dart Futureのtimeoutだけでは上流処理が取り消されないため、接続世代を照合し、遅延応答が新しい状態を書き換えないようにする。

## snapshotとref解決

snapshotのCLI decoderとcommand handlerは同じfilter検証を使い、任意の単一selectorをCommandContextからSnapshotServiceへ渡す。SnapshotServiceは全観測で一意性とref採番を確定してからElementInfo.candidateValueによる完全一致で返却行を絞る。textの表示値と操作照合の信頼性を分離し、操作未対応identifierも観測filterには使える。filter metadata（kind/value/matchedCount/totalCount）はこの段階で確定する。retainPublishedでfilter外のrefを削除し、その後SessionManagerのmax-output制限がさらに返却refを絞る。省略前の全体集計は維持し、filterで隠れた衝突を操作可能と誤認しない。

get handlerはCLIとIPCで対象を検証し、CommandContext経由でSnapshotServiceのread経路を使用する。resolveReadは再観測・一意性・text由来・refの属性比較を共有し、操作resolverはさらにvisibleを検証する。どちらもrefを発行せず、getはmutationを呼ばない。countは一意性必須resolverを使わず、capability確認後にinspectのcandidateValue完全一致を集計する。未知型textも候補件数へ含めるが、操作可能とみなさない。欠損属性のnullとboundsのFlutter論理pixel単位はhandlerの結果schemaで明示する。

SnapshotServiceは要素情報を正規化し、RefStoreはref→観測世代・selector・要素属性を保持する。key、identifier、対応確認済みtext、typeの順で一意な候補を選ぶ。公開snapshotと内部の事前観測は分離し、事前検証が新しいrefを発行しないようにする。

公開snapshotはselectorごとの一致数を先に集計する線形処理とし、256要素ごとに期限・接続世代を確認してイベントループへ制御を戻す。固定bindingのtextは既知の5型だけを照合可能とする。未知の型はSemantics派生型と区別できないため表示だけに使い、key/typeで操作する。不正な観測objectはadapter内でBACKEND_ERRORへ分類する。

ElementInfo.valueは信頼できるselector候補、candidateValueは衝突し得る観測値を返す。textの重複集計・再観測・waitにはcandidateValueを使って未知の型も数え、単独の由来未確認textはUNRESOLVABLE_TARGETとする。

ここでの`ElementInfo.value`はselector候補の取得であり、入力値のread APIではない。[Issue #14の将来設計](semantics-selector-state-design.md)はdisplay、照合根拠、型付き値/状態を分離する。固定bindingのraw診断属性はstring化・省略され得るため、adapterが型付きstateとして公開できる根拠にはしない。Semantics階層とWidgetの対応ID、属性の由来、操作別capabilityは上流依存として残る。現行DTO/CLIへの追加実装は本設計に含めない。

Marionetteの要素一覧は完全なツリーではなく、Semanticsの表示用textがTextMatcherに対応しない場合がある。配列添字をselectorにせず、対象を確定できなければ読み取り情報と理由を返す。上流は最初の一致を選ぶため、契約テストには重複・Semanticsラッパー・非表示要素を含める。

事前観測では原子的な対象保証にならない制約はSPECに従う。アプリ側への永続ID拡張追加は初版に持ち込まない。

## 共通契約の所有（SSOT/SOLIDレビュー）

結果のsession有無は`protocol/command_scope.dart`の`usesSession`を正本とする。CLIの通常解析・構文エラー回復・Invocationと、IPCのRequest・client・server・SessionManagerが同じ判定を使う。`close --all`の引数エラーでもsessionはnullになり、オプション値として渡された文字列をflagに読み替えない。IPCのworkflowは実行要求だけなのでRequestがaction=runとして判定する。

`commands/*_request.dart`は副作用のない入力定義・検証を持ち、handlerは観測・操作を担当する。`wait_request.dart`は時間待機と対象待機を別の型にし、対象待機のref/selector排他、state、poll間隔をCLIとdaemonで共有する。workflow schemaのstate・poll範囲もこの定義から組み立てる。workflow v1にrefや時間待機を追加するものではない。

`SessionActionPolicy`はpolicyと保留承認を非公開状態として所有し、authorizeにはRequestと接続世代だけを渡す。Session本体・CommandContext・handlerへ依存しない。find/batch/workflowは入力定義を使って内包操作を調べ、findは検証後にactionを解釈する。Sessionは切断時の承認失効だけを要求する。`architecture_test.dart`がpolicyからsession実行層への推移的依存の再導入を拒否する。

単一closeと全体closeは`SessionManager._disconnectSession`でURI所有権・refの失効、切断完了待ち、失敗の分類を共有する。Sessionは最後の切断Futureを保持し、アプリ終了通知やtimeoutが先にdiscardした場合も後続closeへ同じ結果を返す。disconnectを重複送信せず、切断完了未確認を成功として返さない。録画確定と所有アプリの停止は従来の各所有者が担当する。

## コマンド拡張境界

`find`は表示条件から選んだElementInfoを`SnapshotService.uniqueTarget`へ渡す。matcher候補は1回の再観測からkey/identifier/text/typeの順に選び、`ObservedQuery`としてselectorと選択時属性を保持する。実操作の直前に通常のresolverがその属性も比較し、同じkeyでも置き換わった対象はSTALE_REF / not_sentにする。ObservedQueryは要求内だけで使用し、IPC入力や公開refとして受理しない。

`drag`は`CommandContext.performTargets`から`SnapshotService.resolveAll`を呼び、両対象のref・属性・一意性・可視性を同じinspect結果で確認する。すべて通った後だけ共通mutation経路でrefを失効させ、1回送る。対象の検証失敗では操作せずrefを維持する。再観測とアプリ操作自体の原子性を保証するものではない。

`batch_loader`は全argvの構文・重複option・コマンドparamsだけを解析する。親の共通オプション解決は再実行せず、上書き済みの環境session/timeoutを再検証しない。snapshot差分は構造等価な行をhashで数え、重複件数を維持して比較する。逐次総当たりの二乗時間を避け、ループ内でも同じ期限を確認する。

通常のアプリ操作コマンドはCLI parserとdaemonのCommandRegistryへ同じコマンド名を登録する。recordはSessionManagerの共通session queueでRecordServiceへ分岐する。platformがflutterの場合だけ接続済みbackendとURIを渡し、他の録画はVM Service非依存で扱う。handlerはIPC paramsを信頼せず、未知field、型、必須・排他条件をmutation開始前に再検証する。ref／selectorと有限数の共通検証は`commands/arguments.dart`へ集約する。

CommandContextにsession実行、対象解決、期限確認、ref失効、mutationの1回送信を集約する。handlerは独自のqueue、retry、session生成、ref保存、接続破棄を実装しない。外部のCLI組立向けの型は`lib/marionette_agent.dart`から公開し、内部handlerは必要なファイルを直接importする。上流connectorやresponse mapをコマンド層へ漏らさない。

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

IPC protocolVersionは7で管理対象アプリの起動・終了を追加した（6でsession action policyを追加）（5で要求単位のdebug policy、4で共通出力policyとidle設定handshakeを追加）。workflow requestのparamsはworkflow templateとinputs objectのみで、daemonでも全件検証してから接続・selector capabilityを確認する。AgentError.detailsはIPCとwithOutcomeで保持する。配送失敗はunknown/progressKnown:falseにし、UIを再送しない。schema/validateはRuntimeDirectory.prepareを呼ばない。

workflow応答のframe生成・配送失敗はdaemonのfallbackでもunknown/progressKnown:falseとsession名を保持する。CLIのローカル検証はparseと意味検証後も絶対deadlineを確認し、期限を過ぎた成功を返さない。

## ScreenshotのCLI側変換（Issue #13）

`cli/common_options.dart`が形式・品質のroot登録、既定PNG／JPEG品質90、値検証と拡張子規則を所有する。`CliParser`はscreenshotのpathを接続前に検証し、拡張子省略時に選択形式の拡張子を付加する。help/versionと全サブコマンドも共通定義を継承する。形式・品質はInvocationのCommonOptionsからrunnerへ渡し、IPC paramsやbackend adapterへ追加しない。workflow内のscreenshot対応やprotocolVersion変更は行わない。

`cli/artifact_writer.dart`はbackendのPNGを全件復号検証し、注釈を指定した場合はgeometryに従いPNGへ合成してから出力形式へ進む。注釈なしのPNGなら元のバイト列、JPEGなら白背景へ合成した8-bit RGBを固定image 4.9.1のJpegEncoderへ渡す。RGBA／grayscale alpha／palette／16-bitを画素の正規化値で処理し、透過を捨てる前に合成する。encoderに透過の合成を任せないため、JPEG端部のpaddingによる反復合成も避ける。品質0はencoderの最低品質1へ丸められる。imageの内部importは従来のPNG decoderと同じ境界へ集約し、依存更新時は画像fixtureを再検証する。

runnerはCLI開始時の共通絶対deadlineをそのままwriterへ渡す。復号・合成・encode後にも期限を確認してから、従来の全宛先の排他的予約と書込みへ進む。同期codec自体は中断しないが、遅れて得た画像を成功として公開しない。予約後の失敗・TIMEOUTではこの要求の予約file・書込み済みfile・自動directoryを回収する。OSによるcleanup失敗時は残存し得るが、成功pathsを返さず元のエラーを保持する。テストの時計注入により変換後・予約後・書込み後の期限切れをhost負荷によらず検証する。

## 入出力の安全境界

- 画像保存は全宛先をDartの排他的ファイル作成で予約してから書き込む。既存ファイル・ディレクトリ・symlinkを上書きせず、途中失敗時はこの要求で作成したファイルを削除する。予約後に別プロセスが保存先を意図的に差し替える競合までは保証しない。
- workflowのpath入力は通常ファイルに限定し、FIFO等は開く前に引数エラーにする。ストリーム入力は期限付きstdin (`-`)を使う。
- diagnosticsのZoneには終了可能なcollectorを入れ、要求完了時にListへの参照を外す。接続時に登録したlistenerの後発ログは通常のstderr経路へ戻す。

`--debug`の定義・構文エラー時の回復はCommonOptionsが所有する。Request.debugはbool（省略時false）で、daemon全体の設定にはしない。DebugDiagnosticsは固定enumのstage、制限したrequest ID/session、StopwatchのelapsedMs、許可した正規化codeだけを既存logging経路に追加する。CLI解析・runtime・IPC startup/sendとdaemon dispatch/queue/execute/resultを観測できる。daemon側のイベントは既存request Zoneで収集してresponseのdiagnosticsへ入れ、呼出元stderrで再発行する。通常診断と公開JSON schemaVersion=1は変更しない。経過時間はCLI・IPC・daemon dispatch・session queueそれぞれの区間開始から計測するため、区間をまたぐ値の差は所要時間として扱わない。CLIの最終結果が全体の成否を表す。
- ref/selectorの排他・型・空文字と有限数の検証は`commands/arguments.dart`へ集約し、CLIのtarget parserとdaemonの操作handlerで共有する。
- 通常コマンドを含む全エラーのテキスト出力にoutcomeを表示し、workflowには進捗既知性、完了step数、失敗stepも付加する。daemonは要求処理開始後の応答生成失敗をunknownへ分類する。

## 内部プラットフォームサービス

`packages/marionette_agent_util`は録画専用ではなく、marionette_agentで必要になるOS／端末別処理を集約する内部パッケージ。CLI/session/protocolやmarionette_mcpへの逆依存を持たない。今後の端末情報等も独立したサービスとして追加する。

```text
CLI parser → RecordService（共通引数検証・エラー変換）
            → RecordingManager（owner・端末排他・保存・終了）
              → ScreenRecorder / RecordingHandle
                → iOS: simctl / Android: adb / macOS: screencapture
                → Web: Chrome CDP lifecycle + macOS screencapture
                → Flutter: FlutterScreenRecorder → PngScreenRecorder + ffmpeg
```

CLIは同一repo内の`../marionette_agent_util`へpath依存し、両パッケージはpublish_to:noneとする。配布は両パッケージを含むcheckoutからの起動またはCLIのコンパイル済みバイナリを使用する。隣接する参考リポジトリへのpath依存は導入しない。

record start、connect、launchがdaemonを自動起動できる。sessionは録画だけでも予約・保持でき、後からVM Serviceを接続できる。recordのstart/stop/statusとcloseは既存session queueで直列化し、長時間のフレーム処理はqueue外で継続する。録画にはUI mutationのExecution.boundを使わず、utilが開始期限・停止後の有界cleanup・状態を管理する。VM Serviceのepoch破棄は録画handleへ波及しない。Flutter録画用接続の取得失敗はその録画を失敗へ遷移させる。

RecordingManagerは開始前にdeviceを予約し、backendの開始確認後に返す。startのbackend待ちは要求期限と30秒上限で打ち切り、遅れて生成されたhandleの停止・予約回収は追跡付きcleanupとして継続する。start時の終了競合や停止失敗でも、handleの終了確認まではdevice予約を解放しない。stopの要求期限超過後も終了処理を保持し、終わるまで同じdeviceへ別録画を開始しない。Androidの自動終了も同じfinalizationへ合流する。closeでは録画を確定してから所有権を解放する。daemonのSIGINT/SIGTERMではRecordingManager.disposeが開始待ち・停止・保存・追跡cleanup全体を60秒に制限する。期限超過時はRecordingHandle.abortで所有プロセスを強制停止し、ファイル読込をキャンセルして出力を閉じる（追加待ちは最大5秒）。stagingと未確定の予約先を保持し、遅延完了で動画を公開しない。Androidは固有remote pathとPIDを照合して強制停止を試みるが、端末切断時の成功は保証しない。OSで進行中のI/Oは取り消しを保証できないため削除と競合させない。

出力先予約、private staging、iOSのSIGINT、Androidの固有remote file名とcmdline照合付きPIDへのSIGINT、adb pull、macOSの起動生存確認・停止はutil内に閉じ込める。CLIのstdoutへ子プロセスの出力を流さず、失敗はPlatformException→AgentErrorへ変換する。未対応linux/windowsもutilでthrowし、CLI parserとdaemonの両方で共通検証する。

単体テストは保存保護・端末排他・開始失敗・停止期限・異常終了・終了競合、CLIテストは未接続録画session・ref保持・通信断後の継続・close・未対応platformを検証する。`integration_test/record_smoke.dart`は製品CLIで開始→接続→操作→動画確定→重複stop→上書き拒否→close確定を確認する。実動画を復号して画面変化を確認する。

### 非表示アプリの描画録画（Issue #20）

`ScreenshotConnectionBackend`は任意のbackend能力で、録画専用`ScreenshotConnection`の作成だけを公開する。`MarionetteBackend`が上流connectorを別インスタンスで開き、captureとdisconnectを提供する。この接続ではinteraction providerをdiscoverせず、切断時にkeyboard.releaseを呼ばない。操作sessionの接続・epoch・refとは独立する。

`FlutterScreenRecorder`はこの接続の所有・開始期限・base64変換を扱うadapter。上流内部importは`marionette_backend.dart`に限定する。utilの`PngScreenRecorder`はcapture/closeコールバックだけに依存し、PNG寸法検証、逐次ファイル保存、単調時計の取得時刻、ffconcatによるVFR変換を所有する。RecordingManagerへ録画ごとにScreenRecorderを注入し、既存の保存保護・停止・close・遅延cleanupを共有する。個別captureは5秒、feedの終了は5秒、ffmpeg変換は30秒で制限する。取得エラーを成功動画に変えず、復旧用stagingにはPNGと生成途中の動画が残る場合がある。

macOS fixtureのMainFlutterWindowは明示環境変数でNSWindowの表示を抑え、FlutterEngineを開始する。Flutter側はdebug限定の`enableHeadlessRendering()`でhidden/paused/detachedの通知を変更せず、16ms間隔のscheduleForcedFrameでフレーム生成を維持する。可視状態への復帰とdisposeでtimerを停止する。他のアプリは自分のnative windowを隠す処理を持つ必要がある。通常起動はopt-inなしで既存のlifecycleに従う。iOS/Android/Webはそれぞれの標準ヘッドレス起動手段を使い、testerによるプラットフォーム模倣はしない。

`record_smoke.dart`はplatform=flutterの場合connectまたはlaunchを先に行い、testerを含む5環境共通で操作・録画保存・重複stop・既存出力保護・closeによる保存を検証する。PNG recorderの単体テストは取得失敗・寸法変更・途中abort・変換失敗・実取得間隔を扱い、widgetテストは描画維持のopt-inと解除を検証する。

## 共通オプション（Issue #2・#8）

`cli/common_options.dart`が全共通オプションの名前、help、CLI既定値、ArgParser登録、重複検出、構文エラー回復、オプション固有の値検証とCommonOptionsを所有する。CliParserはrootへ一度登録し、argsの継承によって全command／subcommandへ適用する。個別command parserに定義を複写しない。session名・duration・出力上限の共通値域検証はprotocolに配置し、CLIもIPCも同じ関数を呼ぶ。

CliParserは呼出元のPlatform.environment（テストでは注入したmap）をCommonOptions.createParserへ渡す。session／timeoutのArgParser既定値を環境変数 > 組込み既定値で設定し、argsが明示CLIを優先する。検証は選択後にだけ実行し、空値を未設定として扱わない。構文エラー回復も同じparserのsession既定値を使い、環境解決を重複実装しない。runnerは選択されたtimeoutを解析開始前の時刻からの絶対deadlineへ変換する既存経路を使い、daemonやsession queueは環境変数を再解決しない。

Requestは`maxOutput`と`outputJson`をparams外に持つ。`output/content.dart`の項目serializerをdaemonの制限とCLIの表示が共有し、code point予算を一致させる。SessionManagerはqueue内で公開snapshotを完成させた後に制限し、SnapshotService.retainPublishedで返却generationの省略refを削除してからqueueを解放する。workflow finalSnapshotもこの経路を通る。未公開refを後続要求から利用できる時間窓を作らない。nonceはrendererだけがCLI呼出しごとに生成し、JSONでは対象dataにmetadataとして付加する。

DaemonClientは起動時idle値を内部daemon引数で渡す。idle既定値と値域検証はprotocolの定義を共用し、内部daemon引数のCLI解析だけCommonOptionsを利用する。handshakeとprivate metadataは確定したidleTimeoutMsを含み、clientは明示値との不一致を要求送信前に拒否する。起動lock取得後の再openでも同じ照合を行う。省略時に既存値を上書きせず、設定のためだけのdaemon再起動も行わない。

DaemonServerはclient受信／配送とSessionManagerのpendingを監視し、全queueが空になってからidle timerを開始する。期限切れqueue entryも実際にdrainするまでpendingから除かない。queue完了通知はhealth probe後のtimer未設定を回復するが、既存のidle intervalは延長しない。health probe実行中の期限到達は完了まで延期する。timerは通常のcloseへ合流するため、record確定・全session破棄・socket削除・寿命lock解放を共有する。

## 全session終了（Issue #6）

CLI parserはclose --allをparams:{all:true}へ変換し、共通--sessionの明示との併用を拒否する。DaemonClientは不在時にsession:nullと空sessionsを返す。SessionManagerは受付時の同期予約と既存session queueを管理の直列化境界とし、stoppingを立てて対象を固定する。queue内の実行前検査は待機要求をnot_sentで拒否する。既存queueへのbarrierで実行中の完了を共通期限まで待ち、各sessionの録画確定とdisconnectを並行して集計する。

Session.interruptは現在のExecutionだけを起こし、Execution.boundは自身のsentからunknown/not_sentを決める。完了時にlistenerを削除する。世代失効は従来のdiscardに集約し、そのFutureを全体closeだけが期限付きで待って切断失敗を観測する。workflowも各childの同じboundを使い進捗を保持する。集約結果の配送はDaemonServerの既存onEmpty、shutdown、socket削除と寿命lock解放へ合流し、非受信clientの有界破棄を維持する。公開結果と競合の正本はSPECのclose --all節。

## Webディスプレイ録画（Issue #16）

`web_target.dart`が`display:<index>@<local page endpoint>`の閉じた構文を定義する。RecordingTargetのkeyはWebも`macos:<display>`へ写し、RecordingManagerの同期予約でWeb同士・macosとの物理対象排他を共有する。extensionはRecordingTargetが持ち、Web/macOSはMOV、iOS/AndroidはMP4としてvalidationとstaging名を一致させる。

`WebScreenRecorder`は専用HttpClient（proxyなし）で明示したloopback pageに接続し、Browser.getVersion・Target.getTargetInfo・Inspector.enableを期限内に確認する。CDPのrawエラーは公開せず、許可された説明へ変換する。遅延WebSocket upgradeは閉じる。Chromeとの接続は監視専用で、ページ操作・画像転送・VM Serviceには使わない。

Chrome検証後に同じPlatformScreenRecorderのmacos backendへ明示したdisplayを渡す。wrapper handleはtab終了・crash・接続断を失敗としてnative stopへ合流させる。開始中切断時も後から返ったnative handleを停止する。nativeのisRunning/endedを保持して、終了未確認のdisplay予約を解放しない。通常stop/abortで自分のCDP接続だけを閉じ、Chromeや他のタブを終了しない。CLI側は従来のRecordServiceとsession queue、共通エラー変換をそのまま使う。

Web開始時はCoreGraphicsの`CGPreflightScreenCaptureAccess`をDart FFIで読み取り、未許可ならChrome接続・native録画の前にIO_ERRORで拒否する。許可要求APIは呼ばない。APIを利用できない環境はUNSUPPORTED_CAPABILITYとする。

## Flutter向け追加機能

契約は[SPECのFlutter向け拡張](SPEC.md#flutter向け拡張)と[追加コマンド仕様](ja/cli-parity.ja.md)を正本とする。

- `marionette_agent_flutter`は任意のdebug専用provider。public Widget/State APIで属性を読む。controller値と表示textを別fieldにし、パスワード値は送信しない。mounted Widgetの観測、対象の再照合と有限のinteraction集合を固定名extensionに閉じ込める。完全Semantics treeや永続IDは導入しない。
- `MarionetteBackend`だけがproviderの登録検出・version確認・DTO変換・固定binding APIを扱う。未登録ならstock観測を使用する。`InteractionBackend`と`ClipboardBackend`は任意capabilityで、通常commandsへ上流mapを露出しない。
- snapshotの絞り込みは全観測の衝突判定・採番後、ref保持の確定前に行う。findによる位置選択も一意な既存matcherへ変換して共通action経路へ渡す。cropは撮影前後の対象照合と明示geometryを使い、artifact writerの排他的保存を共用する。diffはCLIでbaselineを読み、画像または非公開のread観測と比較する。clipboard write/copyは送信結果を追跡するが、UI refを失効させないeffect経路を使う。
- batchはsession queueを1枠占有し、各stepは別Executionで1回送信ガードを維持する。失敗時はそこで止まり、進捗を返す。workflow v1の構文は変更しない。
- action policyはsession queue内の実行前に検査し、find/batch/workflowの内包操作も検査する。保留要求はsessionの接続世代と有効期限へ固定し、承認時に1回だけ取り出して通常の対象解決を実行する。close／切断は保留を破棄する。policyは同一ユーザーが変更できるopt-in機能で、IPCの認可境界ではない。
- config、connection state、diff、install/upgradeはCLI側のファイル処理。接続stateの認証URIはprivate IPCから0600の新規ファイルへ書き、公開応答へ戻さない。namespaceはruntimeの名前を分離する。doctorは通常read-onlyで、fix指定時だけ自身所有runtime directoryのmodeを修復する。
- `marionette_agent_util`がdevice列挙とFPS変換のプロセスを所有する。FPSはprivate stagingでの録画確定後変換で、native取得頻度を保証しない。restartは同じ録画queue内でstop→startを行い、旧動画を確定する。新規開始の失敗時に旧録画を再開しない。

## ハイブリッド実行環境の所有権

CLI catalogのlaunchは引数をutilのLaunchOptionsで検証してIPCへ渡す。SessionManagerはsessionを同期予約し、policyを適用した後でApplicationLauncher.startを呼ぶ。utilから返った所有RunningApplicationをsessionへ保持し、接続・最初のinspectまで成功したときにlaunchを成功として返す。接続には既存_connectを共用し、URI所有権・接続世代・refのルールを複製しない。通常のconnectはアプリ所有権を取得しない。

marionette_agent_util/src/applicationがLaunchOptions、PlatformApplicationLauncher、RunningApplication、OwnedProcessを提供する。platform別Flutter/simctl/emulator/adb引数、SDK探索、private一時領域、project排他、URI発見と実行終了をutilに閉じる。utilはCLI、IPC、Marionette backendへ依存しない。アプリのMarionette接続・観測はagentのbackend adapterが担当する。macOSアプリ内のNSWindow／描画維持はFlutterアプリ側のopt-inであり、Dart CLIからnative viewを生成しない。

OwnedProcessは引数配列で起動し、stdoutを有界に保持してFlutter machineのapp.startを解釈する。WebはURI出力に加えて該当appのapp.startedを待ち、Flutter初期化前の接続を避ける。生ログはstderrへ転送しない。app.stopで正常終了を要求し、期限超過では所有Processへsignalを送る。名前による一括killをしない。iOSは専用device setを作成・shutdown/deleteする。Androidは新規の読み取り専用Emulatorだけを所有し、共有adb serverは終了しない。起動中のdisposeと遅延Process.startも所有側で回収する。

closeは既存RecordingManagerによる確定後にRunningApplication.stopを呼び、その後にsessionを廃棄する。アプリ終了通知は該当handleがまだ同じsessionに属する場合だけ世代を失効する。close --allとdaemon disposeも同じutilの終了処理を使う。CLI側のテストで起動・接続準備失敗・policy・外部接続の非所有・異常終了を確認し、util側は実fixture processで開始・timeout・中断・project排他・終了を確認する。
