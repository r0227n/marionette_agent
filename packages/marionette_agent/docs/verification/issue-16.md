# Issue #16 — Webディスプレイ録画の検証記録

状態: developとの競合を解消し、統合後のCLIでWebの入力・画面切替・ブラウザーUI・OSダイアログ、stop/close保存、対象タブ終了を実確認済み。**実環境の権限拒否と人間確認は未実施。** Draft PR #36を維持する。

## 対象

- Issue: https://github.com/r0227n/marionette_agent/issues/16
- branch: `feature/issue-16-web-recording`
- base: `7958647`（最新origin/developをfetchして作成、録画基盤PR #19を含む）
- 初回検証対象: code commit `3fb6e142d588d5d7687383ff26c82320668bac83`。
- 追検証対象: merge commit `726356e`（develop `09e8f77`を統合）。競合したSPECの対象範囲とCLI referenceの末尾は双方の仕様を保持して解消。以後は検証記録のみ変更。
- worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-16-web-recording`
- gtr hook: `ran`。utilの`dart pub get`も実行済み。
- 2026-09-13、macOS 26.5.2 / Chrome 152.0.7977.83、Flutter 3.47.2 / Dart 3.13.2 / marionette_flutter 0.6.0。
- Simulator: 専用iPhone 17 / iOS 26.2、`A71FFCD2-0DFC-4C61-8387-EAEC78C15FEA`。共有利用記録へ予約・解放を記録。
- 利用者の補足要件「ブラウザーUIやOSダイアログも必要」に従い、CDPタブ映像ではなく明示display全体のMOVを実装。

## 受入条件と結果

| 条件 | 実装・確認 | 状態 |
| --- | --- | --- |
| 対象・ホスト・範囲・形式・前提 | SPEC、日本語CLI reference、help、util README、方式比較。可視Chrome / macOS / 明示display全体 / 無音MOV | 記載済み |
| 共通start/status/stop | RecordService → RecordingManager → WebScreenRecorder → 既存macOS backend | 実CLI成功 |
| 権限・依存・未対応 | CoreGraphics permission preflight、CDP識別・安全なエラー変換、fake nativeの拒否とtool欠落 | 自動テスト済み、実拒否は未確認 |
| 操作中録画・正常停止・close | 共通sessionテスト、iOS実CLI、Web基本start/status/stop | 追検証でWeb操作/close成功 |
| 異常・期限・排他・ファイル保護 | WebSocket fixtureとRecordingManager。Chrome/ native異常、startup切断、deadline、display共有lock、file/directory/symlink | 自動テスト済み |
| 実CLI動画の復号・内容 | iOSの入力・tapを動画/PNG/snapshotで照合、Web MOV全フレーム復号 | 追検証でWeb操作・OS dialogを動画内で確認 |
| 両package format/analyze/test | 下記 | 成功 |

## 自動検証

両package内で`dart format .`と`dart analyze`を実行し、整形済み・No issues foundを確認した。

- `packages/marionette_agent`: `dart test --concurrency=1`、261 tests passed（develop統合後）。
- `packages/marionette_agent_util`: `dart test`、35 tests passed。
- Web用17テストはローカルHTTP/WebSocket fixtureとnative recorder seamを使う。権限APIがfalseのとき接続も録画も開始せず、保存先予約を回収することを確認。OSのTCC設定を変更した実験ではない。
- macOSの実行元に対する`CGPreflightScreenCaptureAccess`はtrue。許可要求APIや設定変更は行っていない。

## iOS実環境回帰

専用runtime `/tmp/mra-issue-16/ios-runtime`、session `issue-16-ios`。このworktreeのexampleを起動し、同じworktreeの製品Dart entrypointを使用。URIは私有fileから読み、記録や診断へ転記していない。

11呼び出し: record start（iOS）→ connect → snapshot → screenshot → tap tap_button → fill text_input → snapshot → screenshot → record status → record stop → close。すべてexit 0。

期待/実際: Tap count 0 → 1、Not edited → 24 characters。PNGを開いて一致を確認し、`ios-regression.mp4`を`ffmpeg -v error -i <movie> -f null -`で全フレーム復号（exit 0、stderrなし）。録画中もVM Service操作を実行できた。

終了: close成功、daemon metadata不在、Flutter runner `q`でexit 0、専用Simulator shutdown。端末は解放済み。端末自体は再検証用に保持。

## 初回のWeb実環境確認（追検証前の履歴）

専用profileでChromeを起動し、`/json/list`から同梱fixture `integration_test/fixtures/web_recording.html`の唯一のpageを選択。製品CLIへ`display:1@<exact page endpoint>`を渡した。専用runtime `/tmp/mra-issue-16/web-runtime`、session `issue-16-web`。

`record start .../web-start-stop.mov --platform web --device <pair>` → status → stopがすべてexit 0。recording → stopped、4,953,420 bytesを返した。全フレーム復号exit 0、抽出frameの目視でdisplay全体が含まれることを確認した。ただし検証用Chromeは他ウインドウに覆われており、この動画を「操作結果のエビデンス」とは扱わず、公開添付候補から外している。

重複stopは同じstoppedを返し、既存MOVへのstartはIO_ERROR / exit 1、1msの期限はTIMEOUT / exit 5（送信前not_sent）だった。後続statusは以前のstoppedを保持し、closeは成功した。

UI操作ツールは通常profileのChromeを選択し、専用profileへの切替・screenshot取得ができなかった。利用可能なbrowser surfaceにもChromeはなく、`createBrowserTab("chrome", ...)`はBrowser is not available。利用者へ前面表示を依頼した後、未確認項目を残して公開するよう指示を受けた。別アプリを動かした画像で対象タブの操作確認を代用していない。

## develop統合後のWeb追検証

2026-09-13、merge commit `726356e`の製品CLI、専用runtime `/tmp/mra-i16-followup/web-runtime`、session `issue-16-web`。専用Chromeの同梱fixtureをネイティブUI経由で操作した。ブラウザーの入力・クリックは手動相当のUI操作であり、WebのMarionette接続検証ではない。

- `record start` → `status` → `stop`: exit 0、recording → stopped。`web-verified.mov`は15,141,783 bytes、36.936667秒、H.264 / 4096×2304、音声なし。
- 動画冒頭は空の検証フォルダーを表示するOSファイル選択ダイアログ。そのCancel、fixture再読み込み、counter 0 → 1、入力 `Web recording verified` → 22 characters、About screenへの切替を同じ録画内で確認。Chromeのアドレスバー・翻訳ポップアップも映っている。ファイルは送信していない。
- 録画中の `close`: exit 0、closed=true、recording.stopped。`web-close.mov`は4,961,653 bytes、13.588333秒。About → Controlsの切替を含む。
- 対象タブをUIから閉じると `status` はfailed / CONNECTION_LOST、`stop` はexit 3。`close` はexit 0でfailureとrecoveryPathを返す。復旧用capture.movは5.378333秒で全フレーム復号成功。成功動画として扱わない。
- 3本の製品出力を `ffmpeg -v error -i <movie> -f null -` で全フレーム復号し、すべてexit 0 / stderrなし。抽出フレームで内容を目視確認した。
- 公開添付は `web-verified-redacted.mp4` と `web-close-redacted.mp4`。元の全display録画から、左側に重なっていた別タスクのSimulatorとOSメニューバーを黒塗りし、1600×900へ縮小した共有用コピー。時間の切り貼り・操作結果の改変はなく、Chrome UI・対象ページ・OSダイアログは保持。共有用コピーも全フレーム復号成功。PNGはこの共有用動画から抽出。
- 最後のclose後にdaemon metadata/socketがなく、lock fileだけ残ることを確認。自動テストはCLI 261件、util 35件成功、両packageのformat/analyze成功。

実TCC拒否の検証は未実施。現在の実行元は許可済みであり、共有アプリの権限を変更していない。拒否時に開始しない分岐は既存の自動テストで検証済み。iOS実環境回帰は上記の初回commitでの結果で、今回の統合後には再実行していない。

## 人間の再現手順

1. このbranchを使用し、通常利用から分離したChrome profileと未使用loopback portを選ぶ。日本語CLI referenceの起動例に従い、同梱HTML fixtureを開く。Chromeを録画対象displayへ配置し、ブラウザーのアドレスバーとfixtureを見える状態にする。
2. `/json/list`からfixtureのtype=pageを選び、そのwebSocketDebuggerUrlとdisplay番号を組み合わせる。実行元アプリのmacOS画面収録許可を確認する。
3. 新しい0700 private directoryを作り、その配下をMARIONETTE_AGENT_RUNTIME_DIRへ設定する。同じworktreeの`packages/marionette_agent/bin/marionette_agent.dart`を使用する。
4. `--session issue-16-web record start <new absolute .mov> --platform web --device 'display:1@<page WebSocket>' --json`を実行。Controlsでcounterを1へ、Test inputに検証文字列を入力。Aboutへ移動して戻り、Choose FileでOSのfile chooserを表示してCancelする。
5. status → stopを実行し、保存動画を全フレーム復号して、入力前後・About・アドレスバー・native chooserが同じdisplayの証跡に含まれることを確認する。close確定の別動画も取得する。
6. 新しい動画のrecord中に選んだタブを閉じ、status failed / CONNECTION_LOST、stop exit 3、closeがfailureを含むことを確認。復旧用動画を成功動画として扱わない。
7. 実環境の権限拒否を専用の検証環境で確認する。共有利用中のアプリ権限を無断で変更しない。未許可のまま開始するとIO_ERRORと設定hint、動画未生成になることを確認する。
8. record/session/daemonと専用Chromeの終了を確認する。既存のDraft PR #36の検証コメントと結果を照合する。

ローカルの続行記録: `/tmp/mra-issue-16/assignment.json`、CLI結果: `ios-results.json` / `web-results.jsonl`、動画とPNG: 同directoryの`evidence/`。raw runner log・URI・Chrome profileは公開しない。
