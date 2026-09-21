# Issue #20: flutter-testerによるheadless実行の実装可否

> 更新: 以下は当初の調査時点の記録です。その後、利用者から実装と「各プラットフォームの実行環境を使う」ヘッドレス録画の指示を受けました。現在の実装契約は[SPEC](SPEC.md#flutterアプリのヘッドレス録画issue-20)を正とします。その後の追加依頼により、testerと各実行環境を明示選択するlaunchを実装しています。[最新の利用ガイド](ja/headless.ja.md)を参照してください。

調査日: 2026-09-15。調査当時の状態: **技術的には実装可能。提供形態・対応範囲は提案段階で、製品実装は未着手。**

## 調査当時の結論

`flutter-tester`でdebugアプリを起動し、既存CLIからVM Service経由で操作する方式Bは実現可能と判断する。Issueに記録された過去の実測と、現在の固定SDK・依存・developのソースがその判断を支える。基本操作のための新しいMarionette backendや上流機能追加は、調査した範囲では必須ではない。[I1][F1][R1]

主な追加作業は、ビルドと起動、接続準備の確認、プロセス所有権、異常終了と期限超過時の回収である。最初の候補は、**macOS arm64・Flutter 3.47.2・既定800×600/DPR 3・単一実行を対象とした前景の補助runner**。既存の`close`は接続を閉じる役割を維持し、runnerの明示的な終了が自分の起動したアプリを終了させる案を推奨する。これは採用済み仕様ではない。[R2][R3]

自由なviewport、ネイティブ機能の同等性、Linux/Windows・GUI未ログイン環境、並列実行、headless録画まで一括して対応可能とは判定しない。特にviewport指定は単純なCLIオプションの転送では実現できず、別の設計・実証が必要。[F1][F2][F5][R4]

## 調査時に確認した範囲

| 項目 | 確認結果 |
| --- | --- |
| 対象Issue | [#20](https://github.com/r0227n/marionette_agent/issues/20)、OPEN、コメントなし、native blockedBy 0件 |
| 現行基点 | fetch後の`origin/develop`、`d890003afa8f5d99e765324416a539371ebbc0c8` |
| 調査ブランチ | `feature/issue-20-headless-feasibility` |
| 調査worktree | Issue #20専用worktree |
| セットアップ | `git gtr new ... --porcelain`終了0、`hook_status: ran`。CLI・exampleの依存取得成功 |
| 既存PR | all-state一覧をIssue参照・branch・flutter-testerタイトルで照合し、直接対応するPRなし |
| ローカルSDK | Flutter 3.47.2、framework `d3b14c876900e553bc736ca19295fc09e3853e8e`、engine `a804b261645ef8c13eb3d5c44a5c2fb0340c5539`、Dart 3.13.2。SDK内のversion JSONとソースを確認 |
| 固定依存 | 解決済み`marionette_mcp 0.6.0`・`marionette_flutter 0.6.0`を確認。隣接repoの実装は根拠にしていない |
| 今回の実行 | GitHub読取、ソース・仕様・依存・差分の調査、調査文書の整合確認。tester起動・CLI操作・Simulator回帰・自動テストは未実施 |
| GitHubへの書込 | なし。利用者の指示によりIssueコメント・更新を行わない |

この環境にsubagent起動ツールがないため、一次資料の読取りを並行し、このタスク内で調査した。コード・CLI契約・PRは変更していない。本メモの完成はIssueの実装完了を意味しない。

### 過去の実測と今回のソース確認の区別

2026-09-11のPoCは`f76d15e`が対象で、connect/snapshot、tap、fill、swipe、scroll、logs、PNG、JSON/YAML workflowと最終refの別CLI利用が成功したとIssue本文に記録されている。48 CLI呼出しには失敗と調整も含まれ、全テスト合格という結果ではない。300px swipeではPage 1のまま、画面外の`page_result`を参照する検証も失敗し、一時workflowを500pxに調整したケースで成功した。[I1]

今回、このPoCを再実行したり当時のPNGを再閲覧したりしていない。現行exampleは`registerAgentExtensions()`とmapped screenshot providerを追加しており、backendは登録検出時にtyped providerのinspectを使う。したがって、同じFlutter・Marionette版でも現在の観測経路は当時と同一とは限らない。最新developの再検証は実装時の必須作業である。[R1][R4]

## 技術調査

### 1. 起動から既存CLIへ接続する経路はある

Flutter 3.47.2では、`-d flutter-tester`の明示でテスト用deviceが有効になる。`--show-test-device`を追加しないこと自体は障害ではない。tester deviceはdebugのみを受け付け、`BundleBuilder`で指定entrypointをコンパイルしてassetsを用意し、SDKのtesterを`--run-forever --non-interactive`付きで起動する。[F1][F3]

過去PoCの起動コマンドは次のとおり。これは既存Flutterコマンドの参考であり、今回新設した製品コマンドではない。[I1]

```sh
flutter run -d flutter-tester --debug --no-pub \
  --vmservice-out-file=<private-file>
```

`--no-pub`は依存取得を省略するだけで、tester用のビルド自体は行われる。任意entrypointを提供するならFlutterの`--target`へ渡す設計が可能。依存取得の責任、許可するビルド引数、作業ディレクトリとassetsの扱いは契約として定める。[F1]

Flutterの`writeVmServiceFile()`は接続したサービスの`wsAddress`をファイルに書く。ログの文言解析でURIを推定する必要はない。ただしファイル生成と書込みは別で、ファイルの存在だけでは準備完了を保証しない。URI読取り、接続、Marionette登録確認、最初の観測までを起動期限内で確認する設計が必要。[F3][R1]

現行adapterはURIとextensionを扱い、接続処理でSimulatorのUDIDや`simctl`を必須にしていない。既存sessionの直列化・接続世代・ref失効・UI送信一回の経路を共用できる。[R1][R2]

### 2. 難しい部分は長時間プロセスの管理

現在の`SessionManager`が所有するのは接続と録画であり、アプリ起動プロセスではない。`close`はbackendを切断してsessionを破棄する契約。接続先がtesterであることだけを理由にプロセスを終了させると、利用者が別途起動したアプリの所有権と衝突する。[R2][R3]

`cli/process_runner.dart`は期限内に終了する単発コマンド用で、出力を最後まで集め、終了または期限後に子プロセスをkillする。常駐runnerの所有権管理にそのまま使うものではない。Flutter側の`stopApp()`もtesterへkillを送って成功を返し、ここでは終了完了を待たない。終了コード・子プロセス・一時assetsまで含む製品側の回収確認が必要になる。[R5][F1]

補助runnerに持たせる責任の候補:

- 明示されたFlutter実行ファイル、project、entrypointを検証し、引数配列で起動する。
- 固有のprivate一時領域、VM URIファイル、runtime、session、artifact保存先を使う。URIファイルは新規0600、親は0700とし、古いURIを拾わない。
- 子プロセスのstdout/stderrを継続的に排出する。FlutterはURI、アプリは入力値等を出力し得るため、生ログを製品stdoutや公開診断へ転送しない。
- 起動中・利用可能・終了中・終了・失敗を区別し、準備完了前の失敗と使用中の切断を分ける。
- 起動timeoutや終了要求で、自分が作成したrunner/testerと一時ファイルを回収する。親だけの終了を子の終了成功と見なさない。PID再利用や無関係なsessionを対象にしない。
- 切断時は既存の接続世代・refを失効させ、アプリやUI操作を自動再実行しない。

上記は設計案であり、実装・障害注入試験は未実施。OS別プロセス処理を共用サービス化する場合は、既存の内部utilの責務を使い、CLI/session側から上流APIを広げない。[R2][R6]

### 3. viewport指定は別の設計が必要

固定SDKのengine `ConfigureShell()`は物理2400×1800、DPR 3を直接設定し、幅・高さの制約もその値へ固定している。論理サイズは800×600。通常の`flutter run -d flutter-tester`の引数組立てにサイズ・DPRの転送はなく、この初期化コードもコマンドラインのサイズを読まない。[F1][F2]

Flutterにはbindingの`createViewConfigurationFor()`をoverrideする仕組みはある。ただし固定MarionetteBindingはprivate constructorのみで、利用者側の単純な継承による差替え口を提供していない。またRenderViewのレイアウトだけを変えても`FlutterView.physicalSize`が同時に変わるとは限らない。[F4][M1]

現在のコードでは、stock screenshotがFlutterViewの物理サイズを使い、typed providerのvisible判定もphysicalSize/DPRを参照する。mapped screenshot providerはRenderViewのsize・DPRとFlutterViewの一致を要求する。このためMediaQueryやRenderViewだけを変更する案では、操作座標・可視判定・PNG・注釈が一致することを証明できない。[M2][R4]

選択肢は、固定サイズを採用する、app/binding側のサイズ・geometry契約を整える、tester engine側に設定口を設ける等。後二者は追加検証が必要であり、「CLIにwidth/heightオプションを足すだけ」とは見積もれない。初期範囲は固定サイズを推奨する。

通常PNGはbindingの既定上限2000×2000に収めて縮小するため、過去PoCの2000×1500は実装と整合する。論理座標との倍率はDPR 3とは異なる2.5になる。現行mapped screenshotは縮小しない別経路なので、同一条件なら2400×1800がソース上の想定となるが、今回のtester実測ではない。[I1][M2][R4]

### 4. iOS native実行の代用にはならない

testerは独自のPlatformViewと描画surfaceを使う。iOS側のプラグイン登録・権限UI・WebViewなどを備えたiOS embedderではない。公式のFlutterテスト向け説明も、host側plugin実装がない環境で`MissingPluginException`が起き得ること、依存をアプリ側の境界で差し替える方法を説明している。これは通常の`flutter run`全般がplugin非対応という意味ではなく、testerの起動経路と合わせた判断である。[F1][F2][F5]

追加で確認した環境差:

- engineはテスト用localeとして`en_US`・`zh_CN`を設定する。ホストの日本語設定やiPhoneのlocaleがそのまま反映される前提にしない。[F2]
- testerは`FLUTTER_TEST=true`を渡す。Flutterのassert有効時の`defaultTargetPlatform`はこの環境変数があればAndroidになり、明示overrideで変更できる。iOS向けの見た目・スクロール挙動が自動的に選ばれるとは限らない。`dart:io Platform`のOS判定とは別である。[F1][F6]
- 現行providerのclipboard等はFlutterのプラットフォームサービスを呼ぶ。過去にtap/fillが成功したことから、現在の全コマンドの対応を推定しない。[R4]
- FFI/native assets、ネットワーク、フォント、プラグインはアプリごとに確認する。依存を一律に動作可能または不可能と分類しない。[I1][F5]

### 5. doctorとworkflowにも対応範囲の整理が必要

通常の`doctor`はmacOSとiOS Simulatorを診断するため、Simulator不要のheadless利用の合否ゲートとしてそのまま使うのは適切でない。runner固有の事前確認でSDK/testerの存在・版・debug entrypoint等を調べるか、doctorの対象を指定する拡張を別途合意する必要がある。[R7]

現行`reach-controls.yaml`は今も300論理pxのswipeで、`workflow_smoke.dart`は6step完了後に`page_result`を直接検索する。過去の800×600での失敗要因はソース上も依然として考慮が必要。headless用シナリオでは操作対象を可視範囲に置き、対象boundsを踏まえたジェスチャーを選び、ページ状態を明示確認する。500pxを全アプリ共通の既定値へ変更する根拠はない。[I1][R8]

## 提供形態の比較と提案

相対規模はソース構造からの見積りで、工数保証ではない。

| 提供形態 | 実現性・相対規模 | 主な作業 |
| --- | --- | --- |
| 手動起動手順 | 高い・小 | 起動/終了・URI秘匿・固定viewport・対象環境の文書、再現可能な検証シナリオ |
| 前景の補助runner | 高い・中 | 上記に加え、起動待ち・失敗検出・privateファイル・所有プロセスの回収。既存connect/closeを共用 |
| daemonが管理する新CLI機能 | 可能・大 | 上記に加え、公開入出力・IPC・起動所有権・session予約・状態照会・stop・daemon idle/終了時の扱い、競合試験 |
| 自由viewportや複数OSまで同時提供 | 未実証・追加調査 | binding/geometry/engine方針、ホストごとの依存と実行、並列・終了保証 |

実用性と変更範囲から、補助runnerを最初の候補とする。利用イメージは「runnerを前景起動 → 専用sessionで接続を確立 → 別CLIで観測・操作 → closeで接続を閉じる → runnerへの終了要求で所有アプリを終了」。runner用の正式な名前・構文は未決定で、独立した公開コマンドをこのメモで確定しない。

実装前に合意する事項は次のとおり。以下の候補値は利用者の決定ではない。

| 未確定事項 | 初期候補 |
| --- | --- |
| 提供形態 | 前景の補助runner |
| 対象環境 | 過去PoCのmacOS arm64、Flutter 3.47.2を起点に再検証。SDK更新時も受入試験 |
| アプリ前提 | debug＋MarionetteBinding。native依存はアプリ側の差替えまたは検証条件を明記 |
| viewport | 論理800×600、DPR 3固定。実端末の寸法・locale等と同等とは宣言しない |
| 起動と接続 | runnerがproject/entrypoint、起動待ち、private URIと専用sessionの接続を管理。依存は事前取得 |
| 終了 | closeは既存契約を維持。runnerの終了で所有アプリを終了。異常終了の回収上限を定義 |
| 並列・証跡 | 当初は単一実行。固有runtime/session/artifactを使い、PNGと状態で確認。録画は別スコープ |

## 合意後の変更箇所と検証

### 変更候補

- 補助runnerのentrypointと起動管理サービス。配置・配布方法は提供形態に合わせて決める。共通OS処理を分離する場合は内部utilへ置く。[R6]
- headless用のexample検証シナリオ。既存のJSON/YAML workflowと操作結果の検証をviewportへ適合させる。[R8]
- 正式対応範囲・責務・エラーをSPEC、構造をARCHITECTURE、利用方法を日本語CLIリファレンスへ反映する。CLI入力/出力を追加する場合はparser/catalog/helpも更新する。[R2]
- daemon管理方式を選んだ場合のみ、SessionManager、IPC、daemonの起動・idle・shutdownにプロセス所有権を組み込む。操作handlerの複製は不要。[R1][R3]

### 実装時に必要な確認

1. 合意SDK・最新commitでexampleをtesterとして起動し、Simulator接続やアプリウィンドウに依存していないことを確認する。
2. tap/fill/swipe/scroll/logs/PNG、使用済ref拒否、JSON/YAML workflow、最終refの別CLI利用を確認する。成功応答だけでなくカウンター・入力文字数・Page 2・Bottom reachedを観測とPNGで照合する。
3. provider有効の現行exampleと、必要ならstock経路を分けて確認する。mapped screenshotを対応範囲に入れる場合はgeometryと実PNGを照合する。
4. SDK/依存欠落、ビルド失敗、binding未登録、URI未生成・不完全、起動timeout、使用中切断、起動途中の終了、終了timeoutを確認する。子プロセスと一時ファイルの残存、無関係なプロセスへの影響を検査する。
5. 既定800×600で元のworkflowの失敗条件を再確認し、修正したシナリオが操作後の状態まで検証することを示す。
6. コード変更に応じたformat/analyze/関連テスト/全体テストを行う。CLI機能変更なら既存ルールどおりiOS Simulatorでも回帰確認し、証跡と人間向け手順を用意する。

上記は今後の計画。今回の調査では実施していない。今回の依頼は実装可否の調査であり、製品実装・新CLI契約・Draft PR作成の着手を意味しない。

## 一次資料

GitHubの可変masterは版の根拠にせず、Flutterについてはローカルの3.47.2のソースを確認した。Flutter SDK rootは`<Flutter 3.47.2 SDK>`。下記SDK行番号はその版。pub依存は`<PUB_CACHE>/hosted/pub.dev/`の解決済み0.6.0を確認した。

- [I1] [Issue #20の要件と2026-09-11 PoC記録](https://github.com/r0227n/marionette_agent/issues/20)。2026-09-15に`gh issue view`で本文・コメント・依存を読取。
- [F1] [Flutter 3.47.2 flutter_tester.dart](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/packages/flutter_tools/lib/src/tester/flutter_tester.dart): 91行debug制限、122行startApp、137行一時assets、147行build、156行tester起動引数、177行FLUTTER_TEST、213行stopApp。
- [F2] [同SDK tester_main.cc](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/engine/src/flutter/shell/testing/tester_main.cc): 79行ConfigureShell、140行TesterPlatformView、366行locale。
- [F3] [同SDK run.dart](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/packages/flutter_tools/lib/src/commands/run.dart)のvmservice-out-file、[resident_runner.dart](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/packages/flutter_tools/lib/src/resident_runner.dart):1164、[flutter_command_runner.dart](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/packages/flutter_tools/lib/src/runner/flutter_command_runner.dart):405。
- [F4] [RendererBinding.createViewConfigurationFor](https://api.flutter.dev/flutter/rendering/RendererBinding/createViewConfigurationFor.html)、[FlutterView.physicalSize](https://api.flutter.dev/flutter/dart-ui/FlutterView/physicalSize.html)。同SDKの`packages/flutter/lib/src/rendering/binding.dart:370`も照合。
- [F5] [Flutter公式: Plugins in Flutter tests](https://docs.flutter.dev/testing/plugins-in-tests)。host plugin制約とアプリ境界での差替え。
- [F6] [同SDK foundation/_platform_io.dart](https://github.com/flutter/flutter/blob/d3b14c876900e553bc736ca19295fc09e3853e8e/packages/flutter/lib/src/foundation/_platform_io.dart):29〜38のFLUTTER_TESTとoverride。
- [M1] [marionette_flutter 0.6.0](https://pub.dev/packages/marionette_flutter/versions/0.6.0)、解決済み`lib/src/binding/marionette_binding.dart:24`の継承・初期化・private constructor。
- [M2] 同0.6.0の`lib/src/services/screenshot_service.dart:101`以降、`lib/src/binding/marionette_configuration.dart:22`。FlutterViewの物理サイズと最大2000×2000への縮小。
- [R1] [MarionetteBackend](../packages/marionette_agent/lib/src/backend/marionette_backend.dart): connectのprovider検出、inspectの分岐、上流API境界。
- [R2] [SPEC](SPEC.md)、[ARCHITECTURE](ARCHITECTURE.md): 対応範囲、close、session/ref/timeout、責務分離。
- [R3] [SessionManager](../packages/marionette_agent/lib/src/session/session_manager.dart)、[Session](../packages/marionette_agent/lib/src/session/session.dart)、[RuntimeDirectory](../packages/marionette_agent/lib/src/daemon/runtime.dart)。
- [R4] [現行example main](../example/lib/main.dart)、[typed provider](../packages/marionette_agent_util/lib/flutter.dart)、[mapped screenshot](../example/lib/mapped_screenshot.dart)。
- [R5] [期限付きprocess runner](../packages/marionette_agent/lib/src/cli/process_runner.dart)。
- [R6] [内部util](../packages/marionette_agent_util/lib/)、[終了signal処理](../packages/marionette_agent_util/lib/src/lifecycle/termination_signals.dart)、ARCHITECTUREの内部プラットフォームサービス。
- [R7] [Doctor](../packages/marionette_agent/lib/src/cli/doctor.dart): host.osとsimulators.iosの診断。
- [R8] [workflow smoke](../packages/marionette_agent/integration_test/workflow_smoke.dart)、[YAML workflow](../packages/marionette_agent/examples/workflows/reach-controls.yaml)、[JSON workflow](../packages/marionette_agent/examples/workflows/reach-controls.json)。
