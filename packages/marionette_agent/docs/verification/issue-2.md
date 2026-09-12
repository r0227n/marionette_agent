# Issue #2 — 共通安全オプション検証

対象: [Issue #2](https://github.com/r0227n/marionette_agent/issues/2)。Agent検証は完了、人間の確認は未実施。

- Branch: `feature/issue-2-safety-options`
- Worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-2-safety-options`
- Base: `origin/develop` at `f76ebc786b556be4e64674477521d0b1f2c2351c`
- 検証した実装: `857464d169bcf4d5a8eb34740b184d7c4b04e016`（同一の作業差分で検証後にcommit）。以後はこの検証記録のみを追加。
- 実施日: 2026-09-11 JST。macOS 26.5.2、Flutter 3.47.2（d3b14c8769）、Dart 3.13.2、marionette_flutter／marionette_mcp 0.6.0。
- 専用Simulator: iPhone Air / iOS 26.2 / `C66CFC02-289C-4106-8F63-93DF694BB2C4`。他workerの端末を使用していない。

## Agentの検証

`packages/marionette_agent`で実行。

| コマンド | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `dart format .` | 対象コードを整形 | 成功。既存の無関係なtestの整形差分はcommit対象外 |
| `dart analyze` | 診断なし | `No issues found!` |
| `dart test test/safety_options_test.dart test/idle_timeout_test.dart` | 共通grammar、Unicode、ref、idle、起動競合の成功 | 成功（初回16件、その後health probe競合の回帰テスト1件を追加し全体テストで確認） |
| `dart test` | パッケージ全テスト成功 | 152件成功、exit 0（40秒） |
| `git diff --check` | 空白エラーなし | 成功 |
| `MARIONETTE_TEST_VM_URI_FILE=<private-file> MARIONETTE_TEST_EVIDENCE=<new-evidence-dir> dart run integration_test/safety_options_smoke.dart` | 製品CLIと実画面で受入条件を満たす | 29 CLI呼出しと1集約結果がすべて成功 |

`common_options.dart`の定義をrootへ一度登録し、19種類のcommand／subcommandの前後で同じ3オプションが使えることをテスト。既存のsession/json/timeout/help/versionも同じmoduleへ移動した。重複、欠損、不正値、`--`、JSONエラー回復、durationのoverflowを確認した。IPCはv4、公開schemaVersionは1。

renderer／protocol／sessionテストでは、日本語・絵文字、10,000件のlogs、完全な項目単位の制限、nonceの変化と対、JSONのdecode、workflow finalSnapshot、全観測後の採番、省略refのSTALE_REFを確認した。`"日本😀"`のJSON文字列はquote込み5 code pointsで採用、4では省略となる。

daemonテストでは、複数sessionの破棄とlock再取得、0無効化、実行中とqueue待ち、期限切れqueue entry、health probe中のhandshake切断、1秒周期probeによる無期限延命の防止、異なる設定での同時起動を確認した。同時起動の勝者だけが接続を所有し、敗者はINVALID_ARGUMENT／not_sentとなる。

## Simulatorの期待結果と実測

実際の全CLI応答は[秘匿済みJSON記録](issue-2-results.json)。URI・runner logは含めず、接続先と一時出力pathを置換した。全コマンドはこのworktreeの`bin/marionette_agent.dart`を別Dartプロセスで起動した。スクリプトは毎回短い0700のprivate runtimeを作成し、全呼出しの`MARIONETTE_AGENT_RUNTIME_DIR`を固定する。

| 手順／コマンド（共通sessionはissue2） | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `connect <private VM URI> --idle-timeout 10s` | 新daemonを10秒設定で起動 | 成功 |
| `snapshot --content-boundaries --max-output 300`を2回 | text要素行だけが異なるnonceで囲まれ、項目境界で省略 | 21件中10件、11件省略。見出し・件数は境界外。nonceは2回とも異なる |
| `snapshot --content-boundaries --max-output 500 --json` | 有効なJSON、data内に境界／件数metadata | 21件中3件、18件省略。source=snapshot |
| `snapshot --max-output 1 --json` → 省略した番号を`tap` | 全件省略でも採番済みのrefを推測利用できない | 21件全省略、`tap @e96`はexit 4 / STALE_REF / not_sent |
| `tap --key tap_button --idle-timeout 3m` | 稼働値10sと不一致、送信前拒否 | exit 2 / INVALID_ARGUMENT / not_sent。画面のTap countは0のまま |
| `tap --key tap_button` → `fill --key text_input '日本😀'` → `tap --key tap_button` | tapは2回だけ、入力を画面へ反映 | Tap count: 2、入力「日本😀」、4 characters。snapshotとPNGで確認 |
| `logs --content-boundaries`（text／JSON） | entryだけに境界、JSONの文字列を維持 | 4 entries、source=logs、textは対応するBEGIN/END |
| `logs --content-boundaries --max-output 1`（text／JSON） | 空の項目列と正しい省略件数 | originalCount=4 / omittedCount=4 / truncated=true |
| `workflow run wait-longer-than-idle.json --timeout 20000` | 12秒のwaitが10秒idleで中断されない | 12,992ms後にwait自身のTIMEOUT（exit 5 / not_sent）。daemon metadataは存在 |
| 明示`connect` → `snapshot` → 11秒無操作 → `snapshot` | idle終了後に明示再connectが必要 | metadata削除、exit 3 / NOT_CONNECTED / not_sent |
| 再`connect` → `session show` → `snapshot` | refは破棄済み、Flutterアプリの画面状態は維持 | snapshotValid=falseから再観測。Tap count: 2と入力を保持 |
| `close` | 所有sessionとdaemonを片付ける | 成功、所有runtimeのdaemon metadataなし |

12秒のwaitは、存在しないkeyを待つworkflowで意図的にTIMEOUTにした。その既存workflow契約による接続失効後は明示connectし、続くidle終了を別に確認している。失敗したUI操作を再送していない。

## 選択した画像

製品CLIの`screenshot <absolute-path>`で生成した921×2000 PNGを3枚とも開いて目視確認した。境界と省略件数は画像だけでは表現できないため、上記のCLI記録と併せて確認する。

| 添付ファイル | 実際に確認した状態 | bytes / SHA-256 |
| --- | --- | --- |
| `/tmp/mra-i2.OJBhmK/evidence/before.png` | Tap count 0、未入力。エラー系検証の基準画面 | 121288 / `343f2e0af26b1f4999f0e73933fef0a06cce0a63bc734512dfa14bd28ab96f83` |
| `/tmp/mra-i2.OJBhmK/evidence/after.png` | 2回だけtap、日本語と絵文字の入力、4 characters | 125752 / `eb46d71952818a27d606c78dd0f751bc4264ed938926ef7ee1e13e1d9ec95a23` |
| `/tmp/mra-i2.OJBhmK/evidence/reconnected.png` | idle終了と再connect後にも同じ画面を保持 | 125752 / `eb46d71952818a27d606c78dd0f751bc4264ed938926ef7ee1e13e1d9ec95a23` |

後2枚の同一hashは、daemon再接続によって画面が変わっていないことと一致する。静止状態とCLI出力の機能なので動画は使用しなかった。

## 人間の再現手順

- [ ] 対象branchで以下を実施し、CLI結果と3枚の画像を確認する（未実施）。

1. このworktreeを開く。割当Simulatorが空いていることを確認し、`xcrun simctl boot C66CFC02-289C-4106-8F63-93DF694BB2C4`で起動する。初期状態を作るため、既にexampleが動いていれば同端末の`com.example.example`だけを終了してから再起動する。
2. privateな出力領域を作り、exampleを新規起動する。runner logとURIは共有しない。

   ```sh
   umask 077
   MRA_I2_CHECK=$(mktemp -d /tmp/mra-i2-human.XXXXXX)
   export MRA_I2_CHECK
   cd example
   flutter pub get
   flutter run -d C66CFC02-289C-4106-8F63-93DF694BB2C4 --debug --no-pub \
     --vmservice-out-file="$MRA_I2_CHECK/uri" > "$MRA_I2_CHECK/runner.log" 2>&1
   ```

3. 別ターミナルで同じ`MRA_I2_CHECK`の絶対pathを設定し、このworktreeの`packages/marionette_agent`で実行する。新しいevidence directoryを指定し、過去のPNGを上書きしない。

   ```sh
   dart pub get
   MARIONETTE_TEST_VM_URI_FILE="$MRA_I2_CHECK/uri" \
   MARIONETTE_TEST_EVIDENCE="$MRA_I2_CHECK/evidence" \
   dart run integration_test/safety_options_smoke.dart
   ```

4. `Safety options Simulator verification passed`と`results.json`を確認する。text/JSONの境界・件数、エラーのexit/code/outcome、12秒処理後も生存して11秒idle後にNOT_CONNECTEDとなること、PNGの0→2と入力・再接続後の保持を照合する。スクリプトがruntimeを分離し、sessionをcloseする。
5. 自分のFlutter runnerを終了し、割当端末のexampleだけを`xcrun simctl terminate <UDID> com.example.example`で終了する。必要なら同端末をshutdownする。URIファイルを削除し、生ログは公開しない。

実施済みteardown: 自分のCLI session／daemonの終了を確認し、割当端末のexampleをterminate、Flutter runnerをSIGINTで終了した。割当Simulatorは元のShutdown状態へ戻した。認証URIファイルは削除済み。他workerの資源と管理対象skillは変更していない。

## 制約

人間確認は未実施。IPC v3の既存daemonは以前のCLIでcloseしてからv4へ接続する。共通parserと仕様文書はIssue #3との統合時に衝突し得るが、ここでは別branchのmerge／cherry-pickを行っていない。1時間を実時間で待つ検証とidle終了時の録画実環境検証は行っていない（既定値、短時間timer、共通の録画shutdown経路は自動テストで確認）。Issue #2が要求したSimulatorシナリオに未実施項目はない。
