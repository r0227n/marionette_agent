# Issue #12 進捗・検証記録

- Issue: https://github.com/r0227n/marionette_agent/issues/12
- 担当: 専任worker、指定モデル `gpt-6-astra` / reasoning effort `xhigh`
- branch: `feature/issue-12-screenshot-directory`
- worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-12-screenshot-directory`
- 基点: `origin/develop` の `50ccf97f47ecf03a51ea3c5646c9164325570c0b`。hook_status: `ran`。
- 着手日: 2026-09-12 (Asia/Tokyo)
- 全体テスト・Simulator検証日: 2026-09-13 (Asia/Tokyo)
- 検証対象code commit: `8988d693fb00119e1aea9a8e80e200b9dffb92ce`。以後は検証文書だけの更新。
- 記録場所の確認: 現在の`AGENTS.md`は`todo.md`を指定せず、そのfileも存在しない。既存のIssue別記録とissues-to-pr worker手順に従い、このfileを進捗記録とする。
- 状態: Agentの必須検証・画像確認・所有資源解放済み。人間による動作確認は未実施。
- [構造化検証記録](issue-12-results.json)に全37 CLI呼出しの引数・cwd・exit code・text/JSON結果、全13画像の絶対path・hash・目視結果を保存した。snapshotは状態確認に使用した3要素へ絞り、認証URIとraw runner logは含めていない。

## 実装と受入条件

| 受入条件 | 実装／確認方法 | 状態 |
| --- | --- | --- |
| 明示path > directory > 一時保存 | `CommonOptions.screenshotDir`をrunnerからwriterへ渡す。明示path時はdirectoryへ触れない。未指定は従来の一時directory | 自動test・Simulatorのtext/JSON両形式で成功 |
| 同時撮影で上書きしない | directory直下に128bit乱数hex名、全fileの排他的作成。16並行batchで32画像を検証し、同じ明示pathの同時予約でも勝者だけ保存 | 自動test成功。Simulatorの別CLI並行撮影も別pathで成功 |
| 複数画像、保存失敗、絶対path | 連番、PNG検証、予約前後のdeadline確認、既存file／directory／symlink拒否、所有fileのみcleanupを共用 | 自動test成功。Simulatorの全13PNGは絶対path、16保存失敗で既存画像・link先保持 |
| directoryの仕様 | 事前作成必須、自動作成なし、相対pathはCLIのcwd、directory自身のsymlink拒否、権限失敗はIO_ERROR | SPEC／ARCHITECTURE／日本語CLIリファレンス／help更新済み |
| 全体自動検証と実機相当の受入 | 下記の全体テストと割当Simulatorでのシナリオ | 全173test成功。全37 CLI呼出しが期待exit code、全13PNGを開いて画面確認 |

`--screenshot-dir`は全サブコマンドが共通定義から継承し、重複・欠損・空文字・NULを引数エラーにする。出力モード回復も既存の共通grammarを使用する。directoryをIPC／daemon／sessionへ永続化しない。環境変数や設定fileのfallbackは追加しない。

Issue #13と`artifact_writer.dart`、screenshotのhelp／仕様に統合時の重複がある。#13のコードは取り込まず、独立したdevelop基点の#12だけを実装する。example、util、外部repository、skillは変更していない。

## 自動検証

環境: macOS 26.5.2 (25F84)、Dart 3.13.2 stable / macos_arm64。全コマンドは`packages/marionette_agent`で実行。

同じコードへのPhase Aの成功結果を引き継ぎ、統括Agentから高負荷検証の実行枠を受領後に全体testを実行した。Flutter 3.47.2、`marionette_mcp`／`marionette_flutter` 0.6.0を使用。

| コマンド | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `dart format .` | package全体をformatできる | 成功、70 files。既存`artifact_writer_test.dart`の整形だけの差分は戻し、無関係な変更を除外 |
| `dart analyze` | issueなし | 成功、`No issues found!` |
| `dart test --concurrency=1 test/screenshot_directory_test.dart test/screenshot_cli_test.dart test/artifact_writer_test.dart test/safety_options_test.dart test/feature_commands_test.dart` | 保存・共通grammar・製品CLIの関連testが成功 | 成功、34 tests passed（約10秒） |
| `dart test --concurrency=1` | 全test成功 | 173 tests passed、約77秒 |
| `git diff --check`、Markdownローカルリンク確認 | 差分・文書の整合性 | 成功 |

初回の対象testは33成功・1失敗。新規CLI testが`/tmp`を期待したのに対し、macOSの子プロセスの実cwdは`/private/tmp`となった。fixtureを`resolveSymbolicLinks`で正規化し、同じ絶対path比較とPNG byte比較を維持した。製品の保存処理やtimeoutを変更せず再実行し、34件すべて成功した。host contentionはこの失敗の原因ではない。

## Simulator資源と起動

- 専用UDID: `C66CFC02-289C-4106-8F63-93DF694BB2C4`、iPhone Air、iOS 26.2。直前にShutdownを確認してからbootした。
- private directory: `/tmp/mra-p2i12.as1g6usm`、mode 0700。
- runtime: `/tmp/mra-p2i12.as1g6usm/runtime`、session: `p2-issue-12`。
- bundle ID: `com.example.example`。runner PID 61284、daemon PID 62035、app PID 61938。検証後すべて停止確認済み。
- raw URIとrunner logはprivate directory直下、画像・秘匿済み結果は`evidence/`配下に分離した。
- 自分のstatus: `/private/tmp/mra-p2-20260912/worker-12-status.json`。統括専用のlease indexや他workerの記録は変更しない。
- 開始受領をstatusへ記録し、`xcrun simctl list devices available --json`で割当UDIDのShutdownを再確認後、`xcrun simctl boot <UDID>`と`xcrun simctl bootstatus <UDID> -b`を実行した。Booted、exampleプロセスとVM Service、初期fixtureを個別に確認した。

## Simulatorでの操作と観測

以下の全シナリオを実行した。単一のexampleが返す画像は1枚なので、複数PNG応答と同一明示path競合・途中失敗のcleanupは決定的な自動testで検証した。保存機能が対象のため録画は開始しなかった。

準備: このworktreeの`example/`から`flutter run -d "$MRA_I12_UDID" --debug --no-pub --vmservice-out-file="$MRA_I12_DIR/uri"`を起動し、出力を`$MRA_I12_DIR/runner.log`へ保存した。`MRA_I12_UDID`は上記の割当値、`MRA_I12_DIR`は上記private directory。ビルドは15.4秒で成功。runner実行ハンドル／PIDをstatusへ記録し、CLIも同じworktreeから実行した。

```bash
# 以下はアプリ起動後の同じworktreeルートで実行する。
# 再現時はターミナルAで作成した新しいprivate directoryへ置換する。
MRA_I12_DIR=/tmp/mra-p2i12.as1g6usm
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_I12_DIR/runtime"
MRA_I12_CLI="$PWD/packages/marionette_agent/bin/marionette_agent.dart"
MRA_I12_SESSION=p2-issue-12
MRA_I12_URI_FILE="$MRA_I12_DIR/uri"
MRA_I12_URI=$(cat "$MRA_I12_URI_FILE")
mkdir -p -m 700 "$MRA_I12_DIR/evidence/generated"
dart "$MRA_I12_CLI" --session "$MRA_I12_SESSION" connect "$MRA_I12_URI" --json
```

認証URIの値は表示・記録していない。以下の各コマンドは`dart "$MRA_I12_CLI" --session "$MRA_I12_SESSION"`の後へ付けた。textとJSONの両結果は構造化検証記録に収録。相対pathの確認では別CLI subprocessのcwdをprivate directoryに指定し、絶対entrypointと同じruntimeを引き継いだ。

| 手順／コマンド | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `snapshot --json` | 初期Controls | Tap count 0、Not edited、Current page 1 |
| `--screenshot-dir "$MRA_I12_DIR/evidence/generated" screenshot` | textで指定directoryへ初期PNG | 絶対path、921×2000 PNG、Tap count 0を目視 |
| `tap --key tap_button --json` → `snapshot --json` | カウンタだけ1へ変化 | mutationは1回。Tap count 1、他fixture状態を維持 |
| `screenshot --screenshot-dir "$MRA_I12_DIR/evidence/generated" --json` | 初回と別pathに操作後PNG | Tap count 1を目視、初回PNGのhash不変 |
| 同じdirectoryへ2つの別CLIを並行実行（片方text、片方JSON） | 上書きせず2画像保存 | 異なる絶対path、両PNGは操作後画像と同一hash |
| private directoryをcwdにして`screenshot --screenshot-dir evidence/generated`（text／JSON） | caller cwdで相対directoryを解決 | `/private/tmp/.../evidence/generated/`直下に別名保存、Tap count 1 |
| `screenshot <explicit path> --screenshot-dir "$MRA_I12_DIR/missing"`（text／JSON、絶対／相対path） | 明示pathを優先 | 4件すべて成功、caller cwd基準の絶対path、missing未作成 |
| `screenshot`（text／JSON） | 従来の一時保存 | 一意な`marionette-screenshot-*`directory内の`screen.png`、操作後画像と同一hash |
| 不存在directory、通常file、directory symlink、dangling directory symlink、mode 0500 directory（各text／JSON） | 保存拒否、既存状態保持 | 10件ともexit 1／IO_ERROR／not_sent |
| 既存PNG、PNGを指すsymlink、既存directoryを明示pathに指定（各text／JSON） | 上書き・link追跡拒否 | 6件ともexit 1／IO_ERROR／not_sent |
| file集合、hash、link target、未作成path、権限を確認 | 保存失敗による変化なし | 全既存PNG hash不変、余分なfileなし、markerとlink先不変、missing／dangling先なし。0500を0700へ復元 |
| 最後の`snapshot --json`と`screenshot <after-errors.png> --json` | エラー後も接続・UI状態保持 | Tap count 1、Not edited、Current page 1。PNGは操作後画像と同一hash |
| `record status --json`、`close --json` | 録画なし、session終了 | idle、close成功、daemon終了確認済み |

ライブ検証の補助スクリプトもmacOSの`/tmp`と`/private/tmp`のaliasを正規化してfile集合を比較した。connectの正常な秘匿済みINFO診断をstderrに許容した。補助コードの修正にUI操作の再送や製品コード変更は伴わない。

## 画像エビデンス

全13画像を開いた。最初の1枚はControls、Tap count 0、Not edited、Page 1、残る12枚はTap count 1で他の表示が同じだった。全画像921×2000。存在・size確認だけを合否判定にはしていない。

| 添付候補 | 実際の絶対path | 示す挙動／SHA-256 |
| --- | --- | --- |
| 初期状態、textのdirectory保存 | `/tmp/mra-p2i12.as1g6usm/evidence/generated/screen-f495aa87088c501f8822ba8169147b8b.png` | Tap count 0。`343f2e0af26b1f4999f0e73933fef0a06cce0a63bc734512dfa14bd28ab96f83` |
| 操作後、JSONのdirectory保存 | `/tmp/mra-p2i12.as1g6usm/evidence/generated/screen-041768063a49b595e1234e964431d1ae.png` | Tap count 1。`f23be97e90f35d6eb7dc194bdca829b13f8f37bd9a86cd2e35f5e5cdc6dff453` |

残る11枚は2枚目と同一SHA-256であり、重複画像として添付から除外した。各path、対応コマンド、寸法、byte数、hash、目視結果は構造化検証記録で保持する。保存先やエラー応答の証拠は同記録と組み合わせて確認する。raw runner logと認証URIは添付しない。

## 終了処理と人間への引き継ぎ

`record status`はidle、録画は未開始。`close`はexit 0で、daemon PID 62035が不在、専用runtimeのsocketとmetadataが削除されたことを確認した。runnerは`q`でexit 0、PID 61284が不在。example PID 61938と割当UDID上の`com.example.example` launchctl serviceが不在であることも確認した。

割当UDIDだけをshutdownし、Shutdownを再確認した。資源解放時刻は2026-09-13 01:32:27 JST。私有URI fileを削除し、raw runner logは非公開領域に分離して保持した。statusにteardownとreleaseを記録した。coordinator専用registryと他workerの資源は変更していない。

人間は利用端末を排他的に確保し、このbranchのexampleを再起動して初期状態へ戻す。ターミナルAで`umask 077`、`MRA_I12_DIR=$(mktemp -d /tmp/mra-p2i12.XXXXXX)`を実行し、その実際のpathをターミナルBへ引き継ぐ。`MRA_I12_UDID`に確保済み端末のUDIDを設定する。Aをこのworktreeの`example/`で開き、上記の`flutter run`を実行して新しいURIを取得する。必要なら先に`flutter pub get`を実行する。

Bは同じworktreeルートで開き、新しい`MRA_I12_DIR`を用いて上記の環境設定・mkdir・connectを実行する。上表の連続撮影、Tap countの変化、明示path優先、相対directory、一時保存、保存失敗を再現する。全37呼出しの正確な引数と期待／実際の応答は構造化検証記録を参照する。初回画像のTap count 0、以後の1、別path保存、前の画像が変わらないことを確認する。最後に`close`でsessionを閉じ、Aに`q`を入力してrunner／appを終了する。録画は不要。

- [x] 全体テスト・Simulator受入・全画像確認・所有資源解放済み
- [ ] 人間による動作確認（未実施のまま引き渡す）

## PR review integration verification (2026-09-13)

Integrated develop through PR #33. Format and analysis passed; all 242 Dart tests passed. Fresh Simulator verification used the final integrated example with the #34 CLI (5088e76): 8 calls confirmed filtered annotation saves directly into the configured directory, a nonexistent directory returns IO_ERROR without invalidating the ref, tapping that ref changes the counter from 0 to 1, and an explicit path overrides a nonexistent directory. Visually inspected both the generated annotation and resulting counter. Evidence: `/tmp/mra-review35.q6ap53rg/evidence/pr34-results.json`, `pr34-annotated.png`, `pr34-after.png`. The #34 session/daemon were closed; the coordinator retains its owned Simulator/runner solely for the sequential #35 verification and will release them afterward. Human verification remains pending.
