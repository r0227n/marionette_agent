# Issue #13: PNG/JPEGと品質指定

対象: https://github.com/r0227n/marionette_agent/issues/13

担当はIssue #13専任worker（gpt-6-astra / xhigh）。branchは`feature/issue-13-screenshot-jpeg`、worktreeは`/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-13-screenshot-jpeg`。基点は`origin/develop`の`50ccf97f47ecf03a51ea3c5646c9164325570c0b`、初期worktreeはclean、依存取得hookは`ran`。

2026-09-12時点は`verification_waiting`。統括Agentの指示により、実装・関連test・文書・Simulatorシナリオまでを準備した。全test、Simulator起動、実画面確認、エビデンス取得、push、Draft PRはまだ行っていない。Issue #8がバッチの高負荷検証枠を使用中であり、再開指示を待つ。人間確認も未実施。

## 受入条件と実装

| 条件 | 実装・定義 | 自動検証 | 実環境 |
| --- | --- | --- | --- |
| 既定PNGとJPEG実形式・拡張子・品質 | CommonOptions、CliParser、runner、artifact_writer。PNG元バイト列、JPEG品質90既定 | PNG完全一致、JPEG SOI・復号寸法・encoder出力、製品CLIで0/90/100 | 未実施 |
| 品質0/100、範囲外、単独指定、形式矛盾 | JPEG指定時だけ0〜100。拡張子はpng / jpg / jpeg。品質0は固定encoderで1と同じ | parser全共通配置、重複・欠損・不正値、text/JSONのINVALID_ARGUMENTとruntime未作成 | 未実施 |
| 自動名・複数画像・透過背景 | 拡張子省略時補完、screen.jpg、自動/指定連番。8-bit RGBへ白合成 | 単一/複数、自動名、RGBA/グレースケールalpha、16-bit/palette、端部画素 | 複数/透過はfixtureで確認、画面のPNG/JPEGは未実施 |
| 期限・非上書き・cleanup | 元の共通deadlineを変換にも適用、変換後に全宛先予約、失敗時に所有artifactだけ削除 | JPEG batchの既存file/directory/live/dangling symlink、後半不正画像、変換/予約/書込み後TIMEOUT | 未実施 |
| 文書・help・進捗 | SPEC、ARCHITECTURE、日本語CLI reference、help、root todo.mdと本記録 | 差分・リンク・契約整合性を確認 | 該当なし |

同期codecは中断せず、前後に期限を確認して遅い成功を防ぐ。OSがcleanupを拒否した場合の残存可能性は文書化した。backend側JPEG、画像diff、lossless保証は対象外。Issue #12の変更は取り込んでいない。統合時にはscreenshot周辺と共通オプション・仕様書の重複を調整する必要がある。

## 自動検証

作業directoryは`packages/marionette_agent`。

```sh
dart format .
dart analyze
dart test --concurrency=1 test/artifact_writer_test.dart test/screenshot_options_test.dart test/screenshot_cli_test.dart test/feature_commands_test.dart test/safety_options_test.dart
```

Dart 3.13.2 / macOS 26.5.2 (25F84) arm64で実行。`dart format .`は70 filesを処理、`dart analyze`はNo issues found、上記対象5ファイルの40 testsはすべて成功（約9秒）。画像writer 16件、製品CLI 2件は個別実行でも成功。最初の画像テストでは2-channel fixture作成時の`setRgba`がalphaを設定しない問題を検出し、fixtureをalpha setterへ修正した。製品側もopaque grayscaleを含め色チャンネルを正規化し、同じ寸法・全端部画素を検証した。timeout延長・assertion緩和は行っていない。host contentionは検出していない。

検証対象は本branchの実装差分。phase 1のcommitはworker報告に記録する。全体検証済みcommitはまだない。example/utilは未変更なので追加の領域別チェックは対象外。

再開後、同じcode commitに対して`dart test --concurrency=1`を実行して結果を追記する。

## Simulator割当と準備

- 専用UDID: `DEDBBEE8-F70D-4CF2-A150-930585F683B0`、iOS 26.2。割当前に前利用者のteardownとShutdownが確認された旨を統括Agentから受領。
- このフェーズでは端末に接触していない。boot直前に`xcrun simctl list devices available`で再確認し、予想外のBooted/利用中なら停止せず統括Agentへ返す。
- 専用private directory: `/tmp/mra-p2i13.5sf2a6zu`（0700）。runtime: 同directoryの`runtime`、session: `p2-issue-13`。URIとraw runner logは直下、選択証跡は`evidence/`へ分離する。
- bundle ID: `com.example.example`。runner未起動、実行handle/PIDなし。recordは今回不要で未開始。
- 状態正本: `/private/tmp/mra-p2-20260912/worker-13-status.json`。boot前に開始ack、runner起動直後にhandle/PIDを記録する。ホスト共通lease indexは統括Agentだけが更新する。

## 再開後の実行手順・期待結果（人間も同じbranchで再現）

現時点で以下は計画であり実施結果ではない。人間が再現する場合も専用端末の空きと割当を確認し、新しい0700 directoryと初期状態のアプリを使う。シェルトレースは無効にし、認証URIを出力しない。

準備用shell（repository root）:

```sh
umask 077
MRA_VERIFY_DIR=$(mktemp -d /tmp/mra-p2i13.XXXXXX)
mkdir -m 700 "$MRA_VERIFY_DIR/evidence"
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_VERIFY_DIR/runtime"
MRA_VERIFY_SESSION=p2-issue-13
MRA_VERIFY_UDID=DEDBBEE8-F70D-4CF2-A150-930585F683B0
MRA_VERIFY_CLI="$PWD/packages/marionette_agent/bin/marionette_agent.dart"
xcrun simctl list devices available
xcrun simctl boot "$MRA_VERIFY_UDID"
xcrun simctl bootstatus "$MRA_VERIFY_UDID" -b
```

runner専用terminalは同じ`MRA_VERIFY_DIR`の実際のpathとUDIDを引き継いで`example/`から実行する。URIは毎回取り直す。worker再開時は準備済みdirectoryを使用し、新規directoryに切替えた場合はstatusも更新する。

```sh
flutter run -d "$MRA_VERIFY_UDID" --debug --no-pub \
  --vmservice-out-file="$MRA_VERIFY_DIR/vm-uri" >"$MRA_VERIFY_DIR/runner.log" 2>&1
```

操作用shellは準備用shellの変数とruntime環境変数を引き継ぐ。CLIはこのworktreeのentrypointを使う。

```sh
MRA_VERIFY_URI=$(cat "$MRA_VERIFY_DIR/vm-uri")
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" connect "$MRA_VERIFY_URI" --json
unset MRA_VERIFY_URI
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" snapshot --json
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" tap --key tap_button
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" snapshot --json
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" screenshot "$MRA_VERIFY_DIR/evidence/default.png"
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" screenshot "$MRA_VERIFY_DIR/evidence/default.jpg" --screenshot-format jpeg --json
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" screenshot "$MRA_VERIFY_DIR/evidence/quality-0.jpg" --screenshot-format jpeg --screenshot-quality 0
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" screenshot "$MRA_VERIFY_DIR/evidence/quality-100.jpeg" --screenshot-format jpeg --screenshot-quality 100 --json
dart "$MRA_VERIFY_CLI" --session "$MRA_VERIFY_SESSION" screenshot --screenshot-format jpeg --json
```

初回snapshotのTap countは0、tap後は1であることを確認する。全PNG/JPEGを復号し、形式・同じ寸法・画面のTap count 1と対応することを確認する。自動JPEGは専用一時directoryのscreen.jpg。生成された画像はすべて開き、選択した画像のpathと示す挙動を記録する。品質0/100の差はファイル容量だけで判定しない。選択画像と対応する秘匿済みtext/JSONを証跡として残す。

| シナリオ | 実行する追加引数・操作 | 期待結果 | 実際 |
| --- | --- | --- | --- |
| 明示PNG | `screenshot <new.png> --screenshot-format png --json` | 同じ画面・PNG復号成功 | 未実施 |
| 拡張子補完 | `screenshot <new-stem> --screenshot-format jpeg` | new-stem.jpgを返す | 未実施 |
| 品質単独/PNG品質 | `screenshot --screenshot-quality 80`、`screenshot --screenshot-format png --screenshot-quality 80 --json` | exit 2 / INVALID_ARGUMENT / not_sent、artifactなし | 未実施 |
| 品質範囲外 | JPEG指定で`--screenshot-quality -1`、`101`、`1.5`をtext/JSONで実行 | exit 2 / INVALID_ARGUMENT / not_sent | 未実施 |
| 形式矛盾 | JPEG指定に`<bad.png>`、既定PNGに`<bad.jpg>` | exit 2 / INVALID_ARGUMENT、ファイル未作成 | 未実施 |
| 既存file | 生成済みdefault.jpgへ同形式で再保存 | exit 1 / IO_ERROR、元のバイト列完全一致 | 未実施 |
| symlink | private directory内の生成済みJPEGへlink.jpgを作り同形式で保存 | IO_ERROR、linkとtargetは不変 | 未実施 |
| 共通期限 | `screenshot <late.jpg> --screenshot-format jpeg --timeout 1 --json` | exit 5 / TIMEOUT、late.jpgなし。接続が失効したら明示connectとsnapshotで観測 | 未実施 |
| 状態保持 | エラー後にsnapshotを取得 | Tap countは1のまま。操作の自動再送なし | 未実施 |

複数画像、透過、変換段階の期限超過は実アプリの単一opaque画面だけでは安定再現できないため、上記fixtureテストで保証する。Simulatorでは実PNG/JPEGと共通期限を確認する。

## 終了・公開前の確認

1. 所有sessionの`record status`で未録画を確認し、`close --json`を実行する。recordを追加した場合は先に`record stop`を完了させる。
2. runtime metadata/socketが消えたことと記録したdaemon PIDの終了を確認する。
3. runner terminalへ`q`を送り、handle/PIDの終了を確認する。detachで済ませない。必要なら割当UDIDとbundle IDを指定して所有appをterminateする。
4. 所有app/runnerが残っていないことを確認して、`xcrun simctl shutdown "$MRA_VERIFY_UDID"`。同UDIDのShutdownを再読し、statusへteardownとreleaseを記録する。他端末には触れない。
5. 不要なURI fileを削除する。raw runner logを公開しない。選択画像を開いて確認し、検証結果・commit・再現手順とともにDraft PRへ全件添付する。
6. clean commit、remote確認、通常push、develop宛Draft PR作成後にhead/base/draft・添付URL・未チェックの人間確認欄を再読する。

PR URL・添付URL・全体検証commit・終了結果は再開後に記録する。Ready化、merge、Issueの手動close、worktree削除は行わない。
