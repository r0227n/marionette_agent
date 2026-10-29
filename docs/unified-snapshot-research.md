# Flutter・OS混在snapshotの影響調査

調査日: 2026-10-28。対象: `feature/native-dialogs` / `6fc3d3a389c06460a72dbae5f688e8d81d645936`。

追記（2026-10-29）: 本調査を受けて、session bindと通常snapshot/tap/swipeへの統合を実装した。以下は調査時点の記録として保持する。現在の契約は[SPEC](SPEC.md#native-ui)と[利用ガイド](https://r0227n.github.io/marionette_agent/en/guides/native-ui/)を参照。

利用者の要件は「snapshotがFlutterとOSの要素を一緒に提示する」こと。その前提で、通常コマンドへの統合と`native`コマンドの分離を比較した。これは設計判断のための調査記録であり、現在のCLI仕様を変更するものではない。以下のコマンド・フィールド案は未実装。

## 結論

**混在snapshotを通常の`snapshot`で提供し、そこに出たrefの`tap`も通常コマンドへ統合することを推奨する。** 一方、座標操作とsource指定のないselectorを自動的に振り分けること、すべての操作を同時に共通化することは推奨しない。内部のFlutter adapterとnative adapterは分離したまま、観測の公開と対象の振り分けを共通のmoduleが担当する。

以前の「nativeで分ける」という判断は、観測も別々であることを前提にしていた。混在snapshotを製品の基本動作とするなら、利用者にrefの取得元を見てコマンドを選び直させる価値は小さい。refの登録情報から操作先を一意に決められる範囲は、共通interfaceで隠せる。

ただし、これはコマンド名を揃える小変更ではない。**主要な工数は、端末の紐付け、観測の公開・失効、前面UIの扱い、policyと実行経路の整合性にある。** 混在snapshotを作る時点で、その多くは操作コマンドを分離しても必要になる。

## 調査方法と範囲

一次資料として、現行SPEC・ARCHITECTURE、DartのCLI/daemon/MCP実装、Swift/Javaのnative runner、既存テスト、Apple/Androidの公式API資料を確認した。既存fake backendを使った再現コードで、snapshot取得順とref失効を実測した。Simulator/Emulatorでの混在snapshotは未実装のため、実機相当の動作確認・性能計測はしていない。

現行契約は[SPECのnative UI](SPEC.md#native-ui)、責務は[ARCHITECTUREのnative UI](ARCHITECTURE.md#native-ui-boundary)を参照する。研究文書は[文書方針](ja/documentation.ja.md)の日英対訳対象外であり、公開利用ガイドやSPECへ未実装の契約は追記しない。

## 現行実装で確認できたこと

| 項目 | 現状と影響 | 一次資料 |
| --- | --- | --- |
| Flutter snapshot | VM接続を要求し、取得前に`session.invalidate()`を呼ぶ。これによりnative observationも消える | [SnapshotService](../lib/src/snapshot/snapshot_service.dart)、[Session](../lib/src/session/session.dart) |
| native snapshot | `NativeService.handle`内で取得・ref発行・sessionへの保存まで行う。Flutter observationは消さない | [NativeService](../lib/src/platform/native/native_service.dart) |
| 公開ref | Flutterは`@eN`とselector+属性、nativeは`@nN`と要素全体+端末を保持する。どちらも操作前に再観測する | [Flutter対象解決](../lib/src/snapshot/snapshot_service.dart)、[native対象解決](../lib/src/platform/native/native_service.dart) |
| 通常tap | `RefQuery`は`@eN`のみ受理する。通常のdispatchもVM接続を前提とする | [TargetQuery](../lib/src/snapshot/target.dart)、[actions](../lib/src/commands/actions.dart)、[SessionManager](../lib/src/session/session_manager.dart) |
| 端末の対応 | 通常の`connect`はURIだけを受け取る。`nativeTarget`は最後に扱ったnative端末であり、Flutterとの対応の証明ではない | [SessionManager](../lib/src/session/session_manager.dart)、[Session](../lib/src/session/session.dart) |
| managed launch | platform/deviceは`ManagedApplication.description`に存在する。起動経路では対応情報の起点にできるが、native runnerの準備やapp identityとの照合は別途必要 | [ManagedApplication](../packages/marionette_agent_platform_interface/lib/src/application/managed_application.dart)、[launcher](../lib/src/platform/application/application_launcher.dart) |
| 失効範囲 | native入力は同じ端末のnative refsとdaemon全体のFlutter refsを失効。Flutter入力は自sessionの両方を失効 | [NativeService](../lib/src/platform/native/native_service.dart)、[Execution](../lib/src/session/session.dart) |
| 操作直列化 | session queueは共通だが、device queueはNativeServiceの内側にある。Flutter操作はそのdevice queueを通らない | [SessionManager](../lib/src/session/session_manager.dart)、[NativeService](../lib/src/platform/native/native_service.dart) |
| policy | 取得元でなくcommand名から判定する。`tap`と`native`は別のpolicy action | [action_policy](../lib/src/session/action_policy.dart) |
| 出力の制限 | `elements`を先頭から予算まで出し、command名に応じて片側だけのrefを残す | [limitContent](../lib/src/output/content.dart)、[SessionManager](../lib/src/session/session_manager.dart) |
| nativeの能力 | DTOにtype/text/identifier/value/package/enabled/boundsがある。window ID・前後関係・depth・clickable・Flutter要素との対応IDはない | [NativeElement](../packages/marionette_agent_platform_interface/lib/src/native/native_ui.dart) |

再現コードでは、同じsessionにfake Flutter/native backendを接続し、次の結果を得た。OS操作は行っていない。

| 手順 | 結果 |
| --- | --- |
| native snapshot → Flutter snapshot → 旧native refでnative tap | `STALE_REF` |
| Flutter snapshot → native snapshot | 両方のobservationを保持 |
| 通常tapへnative refを渡す | `INVALID_ARGUMENT` |
| 有効なnative refでnative tap → 旧Flutter refで通常tap | native入力は1回成功、Flutter側は`STALE_REF` |

したがって、既存2コマンドを一定順で呼んでJSONを連結すれば両方を一時的に保持できるが、それだけでは共通の公開世代、失敗時の処理、出力制限、操作経路が整わない。

## 混在snapshotで解決すべきこと

### 1. 同じ端末・アプリを観測していること

URIから端末を推測したり、最後に使ったnative端末を自動的に組み合わせたりしない。sessionにplatform/device/app identityと紐付けの根拠を持たせる。managed launchが持つ起動情報を使う経路と、外部起動アプリに利用者が明示指定する経路を区別する。手動指定は宣言された対応であり、VM接続との検証済み対応と同一視しない。

iOS runnerは起動時の`MRA_APP_BUNDLE_ID`を使用するが、現在のwire responseには「設定された対象アプリ」を独立して返さない。session側で同じ端末を指定できても、runnerが別のアプリ向けである可能性を照合できるようにする必要がある。Androidでも対象アプリのpackageと観測した要素のpackageを区別する。[iOS runner](../packages/marionette_agent_ios/native/Sources/NativeRunner.swift)、[transport](../packages/marionette_agent_platform_interface/lib/src/native/native_runner.dart)。

再接続、端末変更、アプリ終了、closeで対応情報・ref・pending approvalをどう更新するかも契約に含める。対応が未検証のsessionについて、現行の保守的な全Flutter ref失効を安易に狭めない。

### 2. 「nativeで取得した要素」と「OSだけの要素」は異なる

iOS runnerはSpringBoardのalertがあるか、対象アプリがforegroundでない場合にSpringBoardを選び、それ以外は対象アプリのsnapshotを取る。両方のOS階層を同時取得する実装ではない。また、出力`package`は取得対象のbundleを全子要素へ付けており、各要素の真のプロセス所有者を観測しているわけではない。[iOS runner](../packages/marionette_agent_ios/native/Sources/NativeRunner.swift)。

Android runnerは`By.depth(0)`から取得した各rootをflattenし、`UiObject2.getApplicationPackage()`を出力する。app packageと同じ要素を除外する処理はない。[Android runner](../packages/marionette_agent_android/native/src/androidTest/java/dev/marionette/nativeui/NativeRunner.java)。公式資料でも`getApplicationPackage()`は所属アプリのpackage、`getVisibleBounds()`は可視boundsを返すAPIである。[Android UiObject2](https://developer.android.com/reference/androidx/test/uiautomator/UiObject2)。

このため、Flutterとnativeに同じ見た目の要素が重複して現れ得る。textとboundsの近さだけで同一要素と断定してrefを統合しない。app packageだけでnative要素を除外すると、アプリ内のnative viewを落とす可能性もある。

初期版では`source:flutter|native`を残し、表示をsourceごとにまとめる。取得元がnativeであることと、OS所有のUIであることを別の属性として扱う。OS所有者の判定ができない要素はunknownとし、完全な重複排除は行わない。

### 3. 背後のFlutter要素と操作可能性

Flutterの観測・tapはVM経由、native tapはOS座標入力である。Flutter側の`visible`だけでOSダイアログによる遮蔽を判定する処理は、現行の共通経路にない。[MarionetteBackend](../lib/src/backend/marionette_backend.dart)、[SnapshotService](../lib/src/snapshot/snapshot_service.dart)。混在表示したからといって、画面に対応するすべてのrefがユーザーの指で操作できると保証してはいけない。

推奨する初期ルールは、既知のmodal blockerがある場合、背後のFlutter要素を情報として表示しても操作用refを出さず、理由を付けること。操作前にも状態を確認し、snapshot後にblockerが出た場合も送信前に止める。ただし、常駐するsystem barまで一律にblockerと扱ってはならない。unknownをunblockedに変換せず、保証できない範囲を出力する。

現行DTOだけでは一般的な遮蔽判定はできない。runnerの観測メタデータと対応OS上の検証が必要であり、ここが主な技術的不確実性になる。Appleのsnapshot APIは選択した要素とその子孫の属性を取得するもので、Flutter VMの観測と一体化した時点を返すAPIではない。[Apple snapshot](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding/snapshot%28%29)。

### 4. 取得と公開を分ける

各adapterからrefを発行しない観測結果を取得し、統合側でsourceごとの結果を検証してから、1つの公開世代としてrefを登録する。Flutterとnativeの採番prefixは当面維持できる。prefixは便利な表記だが、操作先の根拠はsession内の登録情報にする。

refにはsource、device/app binding、公開世代、観測時属性、対応操作を結び付ける。両方の取得が成功した後、フィルタ・出力制限を適用し、実際に返したrefだけを保持する。失敗した取得の途中で片側のrefだけを新世代として公開しない。

「一括公開」は内部状態の整合性を意味し、OSとFlutterの同時刻の画面取得を保証しない。取得時刻または開始・終了範囲をsourceごとに持たせ、観測中にdaemon経由の同端末操作が割り込まないようにする。外部操作者やアプリ自身の変化は残るため、操作前の再観測と再送禁止を維持する。

### 5. 一方が取得できない場合

native runner未設定、通信失敗、rootだけの取得、Flutter VM停止、対応外platformは別の状態である。空の配列を返して「OS要素なし」と解釈させない。`ok`、取得範囲が不十分な`limited`、未設定・非対応、失敗をsource単位で区別する。

初期版の明示的な両source取得は、必要な取得が失敗したら全体をエラーとし、新しいrefを公開しない方式を推奨する。root-onlyは現行同様にlimitationを持つ取得結果であり、完全性を宣言しない。片方だけを見るsource指定と既存nativeコマンドを回復経路に残す。

部分成功を同じ要求で返す方式は後続拡張にできるが、単に例外をcatchするだけでは足りない。現在の`Execution.bound`はTIMEOUT/CONNECTION_LOSTでsession世代をretireするため、source単位のdeadline・退役とsession全体の寿命を分ける必要がある。特に全体deadline後に「成功した側のref」を遅れて公開してはいけない。[Execution](../lib/src/session/session.dart)。

### 6. 座標・filter・出力量

Flutter boundsは論理ピクセル、iOS nativeはscreen points、Android nativeはscreen pixels。sourceを混ぜた時点で、boundsの座標系を各行または参照先メタデータから一意に特定できる必要がある。単なるDPR乗算で原点・回転・insetまで変換できるとは仮定しない。[Backend DTO](../lib/src/backend/backend.dart)、[Native DTO](../packages/marionette_agent_platform_interface/lib/src/native/native_ui.dart)。

既存`--interactive`、`--depth`はnative DTOに対応情報がない。`enabled && bounds`をFlutterのinteractiveと同じ意味にしない。初期版では、混在sourceに対する未対応filterは明示的にエラーにし、Flutterだけの取得では現行契約を維持する。`--compact`とtext/type等のfilterもsourceごとの意味と適用範囲を定義する。[snapshot filters](../lib/src/snapshot/snapshot_service.dart)、[NativeElement](../packages/marionette_agent_platform_interface/lib/src/native/native_ui.dart)。

現在の出力予算は行のprefixだけを残す。Flutterの行を大量に先に並べると、重要なOSダイアログが切り捨てられる。source別件数・省略数を残し、既知の前面modalを優先する表示順またはsourceごとの予算配分を定義する。未表示refを両sourceで失効させる。native textもuntrusted contentとして扱う。[出力制限](../lib/src/output/content.dart)、[renderer](../lib/src/cli/renderer.dart)。

## 統合と分離の比較

| 案 | 混在snapshot後の操作 | 得られるもの | 残る負担・リスク | 評価 |
| --- | --- | --- | --- | --- |
| A: 観測・操作とも分離 | snapshotとnative snapshotを個別取得 | 最小の変更 | 一緒に提示する要件を満たさない | 採用しない |
| B: snapshotのみ統合 | `@e`はtap、`@n`はnative tap | 一回で全体を確認でき、操作経路の変更は少ない | refの出自を利用者が解釈し、native側にdeviceを再入力。観測の複雑さはCと大差ない | 段階導入には使える |
| C: snapshotとref tapを統合 | `tap <ref>`で登録済みsourceへ一度だけ送信 | 観測→ref選択→操作が共通になる | router、policy、native-only sessionの受理条件の変更が必要 | 推奨 |
| D: 全操作・selector・座標を自動統合 | 常に同じコマンド、sourceを自動選択 | 表面的には最少のコマンド | 同名対象、重複、座標系、未対応操作、権限の意味が曖昧になる | 現段階では採用しない |

混在snapshotを必須とした場合、Bでも端末紐付け・重複・遮蔽・ref公開・出力制限は解決しなければならない。Cで追加する対象routerは、その登録情報を操作にも利用する。したがって、長期の製品interfaceとしてはCの価値が大きい。

## 推奨する公開interface

以下は設計例であり、現在の実行可能なCLI入力例ではない。

```text
# Flutterとnativeを明示的に紐付けたsession
snapshot
tap @n21
snapshot
tap @e45

# 取得元を限定する診断・回復経路
snapshot --source flutter
snapshot --source native

# native座標操作は対象と座標系を明示する既存経路を維持
native tap --platform ios --device <UDID> --x <points> --y <points>
```

- native未設定の既存sessionでは`snapshot`のFlutter動作を維持する。Web/macOS/testerにiOS/Android runnerを要求しない。
- 両sourceを有効にしたsessionでは`snapshot`が両方を返す。移行初期は明示的な`--source all`で導入し、session設定ができた時点で既定値を切り替える。
- JSONは既存の`elements`を維持し、各行にsourceと座標系、対応操作を追加する。source別の状態・観測範囲・取得時刻はenvelopeに持つ。異種ツリーを一つの親子階層へ無理に変換しない。
- `tap @eN`と`tap @nN`はref登録情報から振り分ける。native refに別deviceを指定して上書きすることは認めない。
- source指定のないselectorと座標tapは既存のFlutter意味を保つ。全sourceを検索して先に見つかった対象を押す方式は採らない。native selectorは既存native経路、または将来の明示source指定で扱う。
- `fill @nN`等の未対応操作は送信前に`UNSUPPORTED_CAPABILITY`とする。refの文法を広げただけで全コマンドに対応したと宣言しない。
- nativeの`swipe`は現在座標形式だけで、通常swipeのref/direction/distanceと同じ契約ではない。native ref swipeを追加するなら、領域内の始終点・単位・端点検証を別途定義する。初期統合はtapまででよい。
- `native snapshot/tap/swipe`は互換・診断・VM非接続時の入口として維持する。両入口は同じref登録・操作制御を使い、実装を複製しない。

## 実装の影響範囲

規模は相対評価であり、所要日数の見積もりではない。

| 領域 | 必要な変更 | 規模 | 主な対象 |
| --- | --- | --- | --- |
| session/端末対応 | 明示binding、app identity、再接続・close・native-only受付、managed launch情報の受け渡し | 大 | [session](../lib/src/session/session.dart)、[manager](../lib/src/session/session_manager.dart)、[application](../packages/marionette_agent_platform_interface/lib/src/application/application.dart) |
| 観測とref | collectとpublishの分離、共通公開世代、source別ref、失敗時の公開中止、両方のretain | 大 | [SnapshotService](../lib/src/snapshot/snapshot_service.dart)、[NativeService](../lib/src/platform/native/native_service.dart) |
| native DTO/runner | app/観測範囲、前面・modal情報、必要ならwindow/depth/capabilities、wire互換性 | 大・要実環境調査 | [DTO](../packages/marionette_agent_platform_interface/lib/src/native/native_ui.dart)、[transport](../packages/marionette_agent_platform_interface/lib/src/native/native_runner.dart)、Swift/Java runner |
| 実行制御 | 同端末のFlutter/native操作のqueue、lock取得順の統一、遅延結果の破棄、失効範囲 | 大 | [Execution](../lib/src/session/session.dart)、[NativeService](../lib/src/platform/native/native_service.dart)、[CommandContext](../lib/src/commands/command_context.dart) |
| tap/対象解決 | source別の再観測とdispatch、native refの受理、unsupported判定 | 中 | [TargetQuery](../lib/src/snapshot/target.dart)、[actions](../lib/src/commands/actions.dart)、[native validation](../lib/src/commands/native_request.dart) |
| policy/confirm | command名だけでなく解決先から必要policy actionを判定。承認後も同じbindingとfresh ref条件を検証 | 中〜大 | [action_policy](../lib/src/session/action_policy.dart) |
| CLI/表示 | source指定、混在メタデータ、filter、出力予算、untrusted boundary、help | 中 | [snapshot parser](../lib/src/cli/commands/observations.dart)、[renderer](../lib/src/cli/renderer.dart)、[content](../lib/src/output/content.dart) |
| MCP | tapのref schema、snapshot source/binding、説明、profileと能力の整合性 | 中 | [catalog](../lib/src/mcp/catalog.dart)、[executor](../lib/src/mcp/executor.dart) |
| 派生読み取り | get boxの単位、get valueの意味、is/find/wait/dragの対象source、snapshot diffの比較属性 | 中・段階的 | [get](../lib/src/commands/get.dart)、[wait](../lib/src/commands/wait.dart)、[find](../lib/src/commands/find.dart)、[diff](../lib/src/cli/observation_diff.dart) |
| batch/workflow | 共通routerの注入、事前capability/policy検証、finalSnapshot両source保持、スキーマ | 中〜大 | [batch](../lib/src/commands/batch.dart)、[workflow](../lib/src/workflow/workflow_runner.dart)、[schema](../lib/src/workflow/schema_catalog.dart) |
| 契約・利用ガイド | SPEC/ARCHITECTURE、native guide、CLI/MCP reference、workflow、同梱skill-dataの日英同期 | 中 | [SPEC](SPEC.md)、[ARCHITECTURE](ARCHITECTURE.md)、[native guide](../website/src/content/docs/en/guides/native-ui.md) |

特に見落としやすい点は次の通り。

1. `tap @nN`を通常tapに追加するだけでは、`deny: [native]`を迂回する可能性がある。source判定はOS観測なしでsession内の登録情報から行い、少なくともnative policyを必須にする。通常tap経由ではtap/native双方を要求する案を推奨し、その意味を文書化する。承認済み要求は端末bindingと世代に固定する。
2. device queueを統合側へ移すと、既存NativeService内のqueueを再取得する設計はデッドロックを招く。session→deviceの順を統一し、下位adapterはqueueを所有しない形に整理する。
3. MCPの共通target schemaはfill/get等でも共有される。正規表現を全体で`@e|@n`に変えるだけでは不十分。コマンド別capabilitiesとエラー契約を揃える。core profileのtapがnativeを実行できるようになる変化も明示する。profileはpolicyの代替にしない。
4. batch/workflowはSessionManagerの通常dispatchとは別にCommandContextを生成する。通常コマンドだけの修正では内部経路に届かない。初期版でnative操作を対象外に残すなら、途中まで実行してから失敗せず、事前に拒否する。
5. workflowの`nativeOnly`は現在「OSスクリーンショットだけのworkflow」の判定であり、native UI操作対応を意味しない。今回の設計でその名称だけを根拠に再利用しない。
6. snapshot diffは`ref`と`reason`以外の行属性を比較する。取得時刻を各行に入れると毎回差分になる。sourceは識別情報として比較し、時刻・公開世代は比較対象から除く契約にする。旧baselineとの互換性も決める。
7. public JSON schemaとIPC版は別管理。既存JSONに必須フィールドや意味変更を導入する場合はversion方針を決める。native runner wire変更も独立して互換性を検証する。[protocol](../lib/src/protocol/protocol.dart)。

## 段階的な導入

1. **観測範囲の実験と契約決定。** iOS/Androidで通常画面、許可ダイアログ、photo picker、キーボード、PlatformViewを取得し、重複・欠落・blocking情報を確認する。両source取得中の画面遷移も観測する。ここで対応範囲を確定する。
2. **bindingと混在snapshot。** 明示sourceで導入し、collect/publish、共通世代、出力制限、同端末queueを整備する。nativeコマンドは維持する。既存Flutter-only snapshotは不変にする。
3. **通常tapへのref統合。** `tap @nN`、policy、再観測、unsupported判定、native-only session、CLI/MCPを一緒に実装する。ここまでを利用者向けの最初の統合機能とする。
4. **後続拡張。** native ref swipe、get/is/find/wait、batch/workflow、明示的な部分成功を、必要なユースケースごとに追加する。完全な重複排除やsource自動選択は前提にしない。

OS runnerのメタデータ調査が先行条件。Cを推奨することは、OSのすべての要素を必ず取得できると保証することではない。Android公式の`getWindowRoots()`には前面順のroot取得があるが、資料上2.4.0追加であり、現行runnerの依存は2.3.0。採用するなら依存更新と実環境検証を含める。[UiDevice](https://developer.android.com/reference/androidx/test/uiautomator/UiDevice)、[現行Gradle](../packages/marionette_agent_android/native/build.gradle.kts)。

## 実装時の受け入れ条件

- 一度のsnapshotに両sourceが入り、native refを通常tapで1回だけ操作できる。操作後のsnapshotと実画面で状態変化を確認する。
- 同じtext・似たboundsの要素を勝手に統合しない。source未指定selectorの意味が変わらない。
- 誤った端末binding、違うsession、世代変更、属性変更、出力から落ちたrefでは入力を送信しない。
- 既知のOS modalの背後にあるFlutter要素を通常の操作可能refとして出さない。snapshot後にmodalが出た場合も送信前チェックを行う。
- 片側の取得失敗、root-only、未設定を区別する。timeout/close後の遅延応答からrefを公開しない。
- native policy deny/confirmが通常tap・MCP・対応する複合実行経路でも有効。承認後のbinding変更を検出する。
- 同端末の別sessionのFlutter/native操作が統合観測の途中へ割り込まない。異なる端末まで不必要に直列化しない。
- Flutter論理座標、iOS points、Android pixels、画面回転の組合せで暗黙変換・誤送信がない。
- native未設定のFlutter-only、Web/macOS/tester、VMなしnative経路が維持される。
- 出力が短い場合もsource別の欠落が分かり、非公開refは使用不能。native textがtrusted metadataとして表示されない。

単体/IPC検証には既存のnative、snapshot、filter、session、policy、MCP、diff、batch/workflowテストを拡張する。実装引き継ぎ時はリポジトリ規定の全テストと日英サイト検証に加え、iOS Simulator/Android Emulatorの両方でアプリ→OS→アプリの往復を録画・確認する。

## 今回の検証

- ソース読解とfake backendによる上記4ケースの再現を実施。混在snapshotや統合tapのコードは実装していない。
- 既存`native_test.dart`、`snapshot_test.dart`、`snapshot_filter_test.dart`の31件が成功。MCPのstartup・引数変換・schemaの3件も成功。既存動作の確認であり、提案した統合機能の検証ではない。
- 実行にはpackage configと一致するFlutter 3.47.2付属Dartおよびローカルの`test-1.31.1/bin/test.dart`を使用した。通常の`dart test`起動は環境既定SDKの不一致、その修正後はpub.devへのアクセス制限で完了しなかったため、既存package configを指定してtest runnerを直接実行した。
- MCPの実stdio/daemonテストはローカルsocket作成の`Operation not permitted`で起動できず、タイムアウトを伴ったため中断した。実通信テストは成功扱いにしていない。
- レポート内の相対リンク67件が存在することを確認。`bun scripts/check-repository-docs.mjs`が成功し、既存の日英11組・ローカルリンク427件を確認した。研究文書のみの追加で公開サイト・現行契約は変更しておらず、サイトbuild/画面確認は実施していない。
- Simulator/Emulatorの新規実行、混在取得の速度・OS要素網羅性の計測は未実施。受け入れ条件に記載した項目は今後の実装検証であり、今回の成功結果ではない。
