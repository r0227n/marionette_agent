# Issue #12 進捗・検証記録

- Issue: https://github.com/r0227n/marionette_agent/issues/12
- 担当: 専任worker、指定モデル `gpt-6-astra` / reasoning effort `xhigh`
- branch: `feature/issue-12-screenshot-directory`
- worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-12-screenshot-directory`
- 基点: `origin/develop` の `50ccf97f47ecf03a51ea3c5646c9164325570c0b`。hook_status: `ran`。
- 着手日: 2026-09-12 (Asia/Tokyo)
- 記録場所の確認: 現在の`AGENTS.md`は`todo.md`を指定せず、そのfileも存在しない。既存のIssue別記録とissues-to-pr worker手順に従い、このfileを進捗記録とする。
- 状態: `verification_waiting`。Phase Aの実装・対象テストは成功。全体テスト、Simulator、公開は統括Agentの再開指示待ち。Issue #8が高負荷検証の実行枠を使用中のため、今回の段階で完了扱いにはしない。

## 実装と受入条件

| 受入条件 | 実装／確認方法 | 状態 |
| --- | --- | --- |
| 明示path > directory > 一時保存 | `CommonOptions.screenshotDir`をrunnerからwriterへ渡す。明示path時はdirectoryへ触れない。未指定は従来の一時directory | 実装済み。writer／製品CLI回帰テスト対象 |
| 同時撮影で上書きしない | directory直下に128bit乱数hex名、全fileの排他的作成。16並行batchで32画像を検証し、同じ明示pathの同時予約でも勝者だけ保存 | 実装済み。回帰テスト対象 |
| 複数画像、保存失敗、絶対path | 連番、PNG検証、予約前後のdeadline確認、既存file／directory／symlink拒否、所有fileのみcleanupを共用 | 実装済み。回帰テスト対象 |
| directoryの仕様 | 事前作成必須、自動作成なし、相対pathはCLIのcwd、directory自身のsymlink拒否、権限失敗はIO_ERROR | SPEC／ARCHITECTURE／日本語CLIリファレンス／help更新済み |
| 全体自動検証と実機相当の受入 | 下記の全体テストと割当Simulatorでのシナリオ | 未実施、次フェーズ |

`--screenshot-dir`は全サブコマンドが共通定義から継承し、重複・欠損・空文字・NULを引数エラーにする。出力モード回復も既存の共通grammarを使用する。directoryをIPC／daemon／sessionへ永続化しない。環境変数や設定fileのfallbackは追加しない。

Issue #13と`artifact_writer.dart`、screenshotのhelp／仕様に統合時の重複がある。#13のコードは取り込まず、独立したdevelop基点の#12だけを実装する。example、util、外部repository、skillは変更していない。

## Phase Aの自動検証

環境: macOS 26.5.2 (25F84)、Dart 3.13.2 stable / macos_arm64。全コマンドは`packages/marionette_agent`で実行。

| コマンド | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `dart format .` | package全体をformatできる | 成功、70 files。既存`artifact_writer_test.dart`の整形だけの差分は戻し、無関係な変更を除外 |
| `dart analyze` | issueなし | 成功、`No issues found!` |
| `dart test --concurrency=1 test/screenshot_directory_test.dart test/screenshot_cli_test.dart test/artifact_writer_test.dart test/safety_options_test.dart test/feature_commands_test.dart` | 保存・共通grammar・製品CLIの関連testが成功 | 成功、34 tests passed（約10秒） |
| `dart test --concurrency=1` | 全test成功 | 未実施。統括Agentのphase boundaryにより次フェーズで実行 |

初回の対象testは33成功・1失敗。新規CLI testが`/tmp`を期待したのに対し、macOSの子プロセスの実cwdは`/private/tmp`となった。fixtureを`resolveSymbolicLinks`で正規化し、同じ絶対path比較とPNG byte比較を維持した。製品の保存処理やtimeoutを変更せず再実行し、34件すべて成功した。host contentionはこの失敗の原因ではない。

## Simulator資源と開始条件

- 専用UDID: `C66CFC02-289C-4106-8F63-93DF694BB2C4`、iOS 26.2。割当時Shutdown。今回のフェーズではboot／run／app操作をしない。
- private directory: `/tmp/mra-p2i12.as1g6usm`、mode 0700。
- runtime: `/tmp/mra-p2i12.as1g6usm/runtime`、session: `p2-issue-12`。
- bundle ID: `com.example.example`。runner、daemon、session、録画は未起動。
- raw URIとrunner logはprivate directory直下、画像・秘匿済み結果は`evidence/`配下に分離する。
- 自分のstatus: `/private/tmp/mra-p2-20260912/worker-12-status.json`。統括専用のlease indexや他workerの記録は変更しない。
- 再開後に開始受領をstatusへ記録し、`xcrun simctl list devices available --json`で割当UDIDを再確認する。予期せずBooted／使用中なら操作せず統括Agentへ報告する。

## 次フェーズの具体的なSimulatorシナリオ

以下は計画であり、実際の結果ではない。再開時に全体テストと検証対象commitを確定してから実行し、期待／実際の結果・exit code・画像との対応を追記する。PNG保存機能が対象のため録画は不要。複数PNG応答と同一明示path競合の決定的な検証は自動testで行う。

準備: このworktreeの`example/`から`flutter run -d "$MRA_I12_UDID" --debug --no-pub --vmservice-out-file="$MRA_I12_DIR/uri"`を起動し、出力を`$MRA_I12_DIR/runner.log`へ保存する。`MRA_I12_UDID`は上記の割当値、`MRA_I12_DIR`は上記private directory。runner実行ハンドル／PIDをstatusへ記録する。CLIは同じworktreeから実行する。

```bash
# 以下はアプリ起動後の同じworktreeルートで実行する。
MRA_I12_DIR=/tmp/mra-p2i12.as1g6usm
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_I12_DIR/runtime"
MRA_I12_CLI="$PWD/packages/marionette_agent/bin/marionette_agent.dart"
MRA_I12_SESSION=p2-issue-12
MRA_I12_URI_FILE="$MRA_I12_DIR/uri"
MRA_I12_URI=$(cat "$MRA_I12_URI_FILE")
mkdir -m 700 "$MRA_I12_DIR/evidence/generated"
dart "$MRA_I12_CLI" --session "$MRA_I12_SESSION" connect "$MRA_I12_URI" --json
```

認証URIの値を表示・記録しない。以下の各コマンドは`dart "$MRA_I12_CLI" --session "$MRA_I12_SESSION"`の後へ付ける。textとJSONの両結果を秘匿済み検証記録へ残す。相対pathの確認では別CLI subprocessのcwdをprivate directoryに指定し、絶対entrypointと同じruntimeを引き継ぐ。

| 手順／コマンド | 期待結果／確認する画面 |
| --- | --- |
| `snapshot --json` | 初期Controls、Tap count 0、Not edited、Current page 1を確認 |
| `--screenshot-dir "$MRA_I12_DIR/evidence/generated" screenshot` | textのpathsは指定directory直下の絶対PNG、初期画面と一致。返却fileを開く |
| `tap --key tap_button --json` → `snapshot` | Tap count 1、他fixture状態は維持 |
| `screenshot --screenshot-dir "$MRA_I12_DIR/evidence/generated" --json` | JSONのpathsは最初と異なり、Tap count 1を描画。最初のPNGのhashは不変。両方を開いて比較 |
| 同じdirectoryへ2つの別CLIを並行実行（片方text、片方JSON） | それぞれ異なる絶対path、PNGはTap count 1、全fileを保存・開いて確認 |
| private directoryをcwdにして`screenshot --screenshot-dir evidence/generated --json` | 相対directoryをそのCLIの実cwdで解決。PNGの画面は維持 |
| `screenshot "$MRA_I12_DIR/evidence/explicit.png" --screenshot-dir "$MRA_I12_DIR/missing" --json` | 明示path成功、missingを作成しない、Tap count 1 |
| `screenshot --json` | 従来の一時directoryに絶対pathを返す。PNGを開いて画面が同一であることを確認し、エビデンス用の対応を記録 |
| `screenshot --screenshot-dir "$MRA_I12_DIR/missing"`および`--json` | text／JSONでIO_ERROR、exit 1、missingを作成しない |
| 既存file／symlinkを明示pathにしたscreenshot、directory自身がsymlinkの場合、mode 0500のdirectory | IO_ERROR、既存file／link target／既存PNG hashは不変。権限はfinally相当で復元 |
| 最後の`snapshot --json`と成功`screenshot` | エラー系を挟んでもTap count 1、画面状態と接続を保持 |

選択した全画像を開き、画像のpath・示す挙動・hashとCLI結果を対応付ける。実画面を示す意味のある画像はすべてDraft PR添付に選び、アップロードURLを最終報告へ記録する。raw runner logと認証URIは添付しない。

## 終了処理と人間への引き継ぎ

再開後の終了時は、所有sessionの`record status`を確認し、録画があれば`record stop`で確定する。`close`でsessionを閉じて所有daemonの終了とsocket／metadata削除を確認する。runnerを`q`などで終了し、runner PIDと割当端末の`com.example.example`の停止を確認する。割当UDIDだけをshutdownしてShutdownを再確認する。URIは不要になったら削除する。statusへteardownの各結果とreleaseを記録して統括Agentへ返す。現在は未使用の予約状態であり、解放完了を申告しない。

人間はこのbranchのexampleを再起動して初期状態へ戻し、新しいprivate directory／runtime／URIで接続する。上記シナリオの連続撮影、Tap countの変化、明示path優先、相対directory、一時保存、保存失敗を再現する。期待する画像とCLI応答を比較し、最後にsession／runner／appを終了する。

- [ ] 全体テスト・Simulator受入・画像確認済み
- [ ] develop宛の1つのDraft PRで検証commit／添付／人間再現手順を再読確認済み
- [ ] 人間による動作確認（未実施のまま引き渡す）
