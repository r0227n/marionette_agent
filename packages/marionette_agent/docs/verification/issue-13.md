# Issue #13: PNG/JPEGと品質指定

対象: https://github.com/r0227n/marionette_agent/issues/13

担当はIssue #13専任worker（gpt-6-astra / xhigh）。branchは`feature/issue-13-screenshot-jpeg`、worktreeは`/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-13-screenshot-jpeg`。基点は`origin/develop`の`50ccf97f47ecf03a51ea3c5646c9164325570c0b`、依存取得hookは`ran`。

2026-09-13 JSTにAgentの必須検証と資源終了確認を完了した。検証対象code commitは`3bf0d26c2bd10435e4f4a69514837d17bbe0a7ee`。フェーズ1の40対象testと文書準備に続き、統括Agentから高負荷検証枠を受領して全testとSimulator検証を行った。その後の変更は本記録・結果JSON・todo.mdのみ。人間の確認は未実施で、PRはDraftとして引き渡す。

## 受入条件と結果

| 条件 | 実装・定義 | 検証結果 |
| --- | --- | --- |
| 既定PNGとJPEG実形式・拡張子・品質 | CommonOptions、CliParser、runner、artifact_writer。PNG元バイト列、JPEG品質90既定 | fixtureで元PNG完全一致・JPEG復号・encoder出力。Simulatorのtext/JSONでも成功 |
| 品質0/100、範囲外、単独指定、形式矛盾 | JPEG指定時だけ0〜100。拡張子png / jpg / jpeg、品質0は固定encoderで1相当 | parser配置・重複・欠損・不正値、text/JSONでINVALID_ARGUMENTと未接続時runtime未作成。Simulatorで0/100保存と-1/101/1.5・単独・形式矛盾を確認 |
| 自動名・複数画像・透過 | 拡張子補完、screen.png/jpg、自動/指定連番、白背景RGB合成 | fixtureで複数画像とRGBA/グレースケールalpha/16-bit/palette/端部画素。Simulatorで自動名、大小拡張子、拡張子省略を確認 |
| 期限・非上書き・cleanup | 元の共通deadlineを変換にも適用、全宛先を排他的予約、所有artifactだけ回収 | fixtureで既存file/directory/live/dangling symlink、後半不正画像、変換/予約/書込み後TIMEOUT。Simulatorでtext/JSONの既存PNG/JPEG・symlink拒否、1msのTIMEOUT、既存バイト列とTap count 1の保持 |
| 文書・help・進捗 | SPEC、ARCHITECTURE、日本語CLI reference、help、root todo.mdと本記録 | 対象test・差分・リンク・契約整合性を確認 |

同期codecは即時中断せず、前後の期限確認で遅い成功を防ぐ。OSがcleanupを拒否する場合の残存可能性は仕様に記載した。backend側JPEG、製品の画像diff、lossless保証は対象外。Issue #12もscreenshot・共通オプション・仕様書周辺を変更するが、このbranchには取り込んでいない。

## 自動検証

環境: macOS 26.5.2 (25F84) arm64、Dart 3.13.2、Flutter 3.47.2 (`d3b14c8769`)、marionette_flutter / marionette_mcp 0.6.0、image 4.9.1。作業directoryは`packages/marionette_agent`。

```sh
dart format .
dart analyze
dart test --concurrency=1 test/artifact_writer_test.dart test/screenshot_options_test.dart test/screenshot_cli_test.dart test/feature_commands_test.dart test/safety_options_test.dart
dart test --concurrency=1
```

formatは70 filesを処理、analyzeはNo issues found。対象5ファイルの40 tests成功（約9秒）。全体は179 tests成功（約83秒）。full logは`/tmp/mra-p2i13.5sf2a6zu/full-test.log`。example/utilは未変更なので領域別の追加チェックは対象外。timeout延長・assertion緩和は行っておらず、host contentionも検出していない。

フェーズ1で2-channel fixtureの`setRgba`がalphaを設定しないことを確認し、alpha setterへ修正した。製品のグレースケール正規化を含め、その後の対象・全体testは上記code commitで成功した。

## Simulator実施結果

iPhone 17 / iOS 26.2、専用UDIDは`DEDBBEE8-F70D-4CF2-A150-930585F683B0`。lease所有者がIssue #13で端末がShutdownであることをboot直前に再確認した。private directoryは`/tmp/mra-p2i13.5sf2a6zu`（0700）、runtimeはその`runtime`、sessionは`p2-issue-13`。raw runner logとURIは添付用evidence directoryから分離した。

このworktreeのexampleをdebug起動し、製品entrypointから合計53回のCLIを呼び出した（初回接続の事前確認とcloseを含む）。[全コマンド・text/JSON結果](issue-13-results.json)に引数、期待/実際のexit、stdoutと秘匿済みdiagnosticsを保存した。認証URIと入力秘密は記録していない。

- 初回snapshotはTap count 0。`tap --key tap_button`を1回だけ実行し、text/JSON snapshotでTap count 1を確認した。
- PNGの既定/明示、JPEG既定90・0・37・100、大小文字の拡張子、自動path、拡張子省略が成功した。返却pathは絶対path、自動directoryは0700。自動画像はbyteを変えずevidenceへ複写し、元の一時directoryを回収した。
- text/JSONの既存PNG/JPEGとsymlink保存はIO_ERROR（exit 1）。元画像のSHA-256、symlinkとtargetは不変。品質単独/PNG品質、-1/101/1.5、形式と拡張子の矛盾、未知形式はINVALID_ARGUMENT（exit 2 / not_sent）、不正pathは未作成。
- text/JSONの1ms screenshotはTIMEOUT（exit 5 / not_sent）。late fileなし。明示connect後のsnapshotでもTap count 1。最後のPNGは最初のPNGと全画素が一致した。
- 製品CLI画像13枚すべてを復号し、919×2000であることを確認した。これはbackendから受け取った画像寸法であり、JPEG変換では変えていない。独立したsimctlの全画面PNGは1206×2622で、システムのステータスバーを含む。
- 上記13枚とsimctlの参照画像1枚をすべて開いた。Tap count 1、空の入力欄とNot edited、Current page 1、Controls/Aboutが同じ配置で表示される。品質0は文字や色の劣化が見えるが、同じ画面に対応する。

検証用の一時スクリプトで、正常なINFO診断を空stderr前提で拒否した箇所と、macOSの`/tmp`→`/private/tmp`正規化前後を比較した箇所を修正した。診断が秘匿済みでsymlink/targetが保持されていることを確認し、負荷を理由とする許容値変更はしていない。UI tapは再送せず、陰性シナリオだけ継続した。製品コードの変更は不要だった。

## 画像エビデンス

保存先はすべて`/tmp/mra-p2i13.5sf2a6zu/evidence/`。各画像を開いて確認済みで、PRへ全14枚を添付する。[画像検証結果](issue-13-image-checks.json)は復号寸法・形式・容量・透過画素数・JPEG量子化情報・同じ画面との画素対応を記録している。

| ファイル | 検証内容 | 形式・寸法・bytes |
| --- | --- | --- |
| default.png | 既定PNG / text | PNG 919×2000 / 117499 |
| explicit.PNG | 明示PNG・大文字拡張子 / JSON | PNG 919×2000 / 117499 |
| default.jpg | JPEG品質省略90 / JSON | JPEG 919×2000 / 117706 |
| quality-0-text.jpg / quality-0-json.jpg | 品質0 / text・JSON | 各JPEG 919×2000 / 54452 |
| quality-37.jpeg | 品質37・.jpeg / JSON | JPEG 919×2000 / 75396 |
| quality-100-text.jpg / quality-100-json.JPEG | 品質100 / text・JSON | 各JPEG 919×2000 / 204386 |
| extensionless.jpg / extensionless-png.png | 拡張子補完 / text・JSON | JPEG 117706 / PNG 117499、各919×2000 |
| automatic-jpeg.jpg / automatic-png.png | 自動pathの画像を同一byteで保管 | JPEG 117706 / PNG 117499、各919×2000 |
| post-errors.png | 全エラー後も同じTap count 1 | PNG 919×2000 / 117499 |
| simulator-post-errors.png | 指定Simulatorの実画面との対応 | PNG 1206×2622、システムUIを含む |

JPEGの先頭輝度量子化係数は品質0/37/90/100で255/22/3/1となり、容量だけでなく指定品質の適用を確認した。同じPNGを基準とするRGB絶対差の平均は品質0で9.769、37で1.449、90で0.428、100で0.305（0〜255の画素値）。製品の画像diff機能ではなく、今回の静止画シーン検証だけの数値である。JPEGがPNGより常に小さくなる保証はなく、この画面でも品質90はPNGより僅かに大きい。

## 人間の再現手順

同じbranchで専用端末の空き・割当を確認し、新しい0700 directoryと初期状態のアプリで再現する。シェルトレースは無効にし、認証URIを出力しない。以下の手順では期待/実際の対応を本検証の結果として記載した。人間自身の確認は未実施。

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

runner専用terminalは同じ`MRA_VERIFY_DIR`の実際のpathとUDIDを引き継いで`example/`から実行する。URIは毎回取り直す。本検証では割当済みprivate directoryを使用した。人間の再現では新しいdirectoryを使う。

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
| 明示PNG | `screenshot <new.png> --screenshot-format png --json` | 同じ画面・PNG復号成功 | 成功 |
| 拡張子補完 | `screenshot <new-stem> --screenshot-format jpeg` | new-stem.jpgを返す | 成功 |
| 品質単独/PNG品質 | `screenshot --screenshot-quality 80`、`screenshot --screenshot-format png --screenshot-quality 80 --json` | exit 2 / INVALID_ARGUMENT / not_sent、artifactなし | 成功 |
| 品質範囲外 | JPEG指定で`--screenshot-quality -1`、`101`、`1.5`をtext/JSONで実行 | exit 2 / INVALID_ARGUMENT / not_sent | 成功 |
| 形式矛盾 | JPEG指定に`<bad.png>`、既定PNGに`<bad.jpg>` | exit 2 / INVALID_ARGUMENT、ファイル未作成 | 成功 |
| 既存file | 生成済みdefault.jpgへ同形式で再保存 | exit 1 / IO_ERROR、元のバイト列完全一致 | 成功 |
| symlink | private directory内の生成済みJPEGへlink.jpgを作り同形式で保存 | IO_ERROR、linkとtargetは不変 | 成功 |
| 共通期限 | `screenshot <late.jpg> --screenshot-format jpeg --timeout 1 --json` | exit 5 / TIMEOUT、late.jpgなし。接続が失効したら明示connectとsnapshotで観測 | 成功 |
| 状態保持 | エラー後にsnapshotを取得 | Tap countは1のまま。操作の自動再送なし | 成功 |

複数画像、透過、変換段階の期限超過は実アプリの単一opaque画面だけでは安定再現できないため、上記fixtureテストで保証する。Simulatorでは実PNG/JPEGと共通期限を確認する。

## 終了確認

`record status --json`はidle（録画は開始していない）。`close --json`はexit 0、daemon PID 67344の終了、metadata/socket消失を確認した。runtimeには寿命/起動lock fileだけが残る。

runner handle 13164へ`q`を送りexit 0。runner PID 66340、app PID 66991と`com.example.example`のlaunchctl serviceが存在しないことを確認した。その後、割当UDIDだけをshutdownし、2026-09-13 01:42 JSTにShutdownを再読。URI fileを削除し、worker statusにteardownとreleaseを記録した。他端末・他worktree・共通lease registryには変更を加えていない。

人間が上記手順を再現した後も、recordがあればstopして所有sessionをcloseし、daemonを確認、runnerを`q`で終了、app終了を確認してから同じ割当端末をshutdownする。detachだけで解放しない。

- [x] Agentの全体test・Simulator・全画像確認・teardown
- [ ] 人間がPRの変更内容と上記手順を確認した

Ready化、merge、Issueの手動close、worktree削除は行わない。
