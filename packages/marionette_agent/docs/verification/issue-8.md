# Issue #8 検証記録

対象: [Issue #8](https://github.com/r0227n/marionette_agent/issues/8)。担当: Astra（割当gpt-6-astra / xhigh）。Agent検証完了、人間確認は未実施。進捗は [todo.md](../../../../todo.md)。

- Branch: `feature/issue-8-environment-defaults`
- Worktree: `/Users/r0227n/Dev/marionette_agent-worktrees/feature-issue-8-environment-defaults`
- Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b` (`origin/develop`)
- 検証対象実装commit: `1c6f25def756b7dae220c52f5b00f63d4960a857`。以後の変更は本記録・秘匿済み結果・todoのみ。
- 実施日: 2026-09-12 JST。macOS 26.5.2、Flutter 3.47.2 (`d3b14c8769`)、Dart 3.13.2、marionette_flutter / marionette_mcp 0.6.0。
- 専用Simulator: iPhone 17 Pro / iOS 26.2 / `022CF629-91E1-48F0-816B-2D86B8CD1D38`。
- runtime: `/tmp/mra-p2i8.hus6s0_l/runtime`、session: `p2-issue-8`、環境timeout: `10000`。私有親directoryは0700。認証URIとraw runner logをevidenceから分離した。

## 受入条件と自動検証

`packages/marionette_agent`で実行。

| 確認 | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `dart format .` | 整形成功 | exit 0。既存artifact_writer_test.dartだけの無関係な整形差分を除外 |
| `dart analyze` | 診断なし | `No issues found!` |
| `dart test test/environment_options_test.dart test/protocol_test.dart test/safety_options_test.dart --concurrency=1` | 新契約と既存共通grammarを維持 | 21件成功 |
| `dart test --concurrency=1` | 全テスト成功 | 170件成功、88秒、exit 0 |
| `dart test test/environment_options_test.dart --concurrency=1` | queueへの実際の受付も確認 | 先行・後続2件のpendingを確認するassertion追加後、7件成功。format / analyzeも再実行済み |
| `git diff --check` | 空白エラーなし | 成功 |

parserは環境mapを注入し、CLIプロセステストは`includeParentEnvironment: false`で必要なPATH/HOME/runtimeと検証対象の環境値だけを渡した。未設定のdefault/30000、環境のみ、CLIの個別上書き、空値、不正な名前、64/65文字、正整数、Duration/DateTime上限、重複、欠損、前後配置、`--`、オプション値内の`--json`/`--session`、構文エラーのsession/JSON回復を検証した。明示CLIに隠れた不正環境値は無視し、選択された不正値はINVALID_ARGUMENT / not_sentとなる。

別製品CLIプロセスのconnect→snapshotで同じ環境sessionを保持した。queueテストはFakeBackendの先行inspectをCompleterで止め、環境timeout=200msの後続tapがqueueに受付済み（pending=2）のままTIMEOUT / not_sentになることを確認した。先行要求解放後もtap呼出しは0回で、次のsnapshotは成功した。タイムアウト値の水増しやassertionの弱体化は行っていない。

初回analyzeでは新テストのSessionManagerメソッド名、初回関連testでは既存text出力の`Outcome`大文字表記との不一致を修正した。製品の挙動不良やhost contentionは観測していない。SDKキャッシュとSimulatorサービスは通常sandboxから利用できないため、承認審査を経て必須コマンドを実行した。example/utilのソース変更はない。

## Simulatorの期待結果と実測

実行した全24 CLI呼出しの引数・環境上書き・exit code・text/JSON応答は [秘匿済み結果](issue-8-results.json)。URIを再取得する手順は下記に示す。すべてこのworktreeの`bin/marionette_agent.dart`を別プロセスで起動した。

起動前に割当端末のShutdownを再確認し、`xcrun simctl boot <割当UDID>` / `bootstatus <割当UDID> -b`、続いて`example/`で`flutter run -d <割当UDID> --debug --no-pub --vmservice-out-file=<private>/vm-uri`を実行。Xcode buildは12.3秒で成功した。

| コマンド／手順（明示しないsession/timeoutは環境値） | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `connect <private VM URI>`、`snapshot`（JSON/text各形式） | 同じ環境sessionに接続し初期画面を観測 | session=p2-issue-8、connected、Tap count: 0、PNG 01 |
| `tap --key tap_button --json` → `snapshot`（JSON/text） | tapを1回だけ実行 | requiresSnapshot=true、Tap count: 1、PNG 02 |
| `snapshot --session p2-issue-8-other --json`、`--session=p2-issue-8-other snapshot` | 明示sessionが環境値を上書き | 両形式でexit 3 / NOT_CONNECTED / not_sent。JSON sessionはp2-issue-8-other |
| 環境のみの`session show --json` | 元の接続は維持 | connected、session=p2-issue-8 |
| 環境session空値、timeout空値／範囲外で`tap --key=tap_button --json` | 操作前に拒否 | 全件exit 2 / INVALID_ARGUMENT / not_sent。session空値の応答sessionはnull |
| timeout環境値0で`tap --key=tap_button`（text） | 操作前に拒否 | exit 2 / INVALID_ARGUMENT、Outcome: not_sent |
| `snapshot --bad --json` | 構文エラーでもsession/JSONを回復 | exit 2、session=p2-issue-8 |
| 再`snapshot --json` | エラー要求で意図しないtapが起きない | Tap count: 1 |
| 不正環境session/timeoutを設定し`tap --key=tap_button --session=p2-issue-8 --timeout=30000`（text） | 明示CLIで両方を上書きして成功 | exit 0、requiresSnapshot=true。次のJSON snapshotとPNG 03でTap count: 2 |
| `record status --json` → 両sessionの`close --json` | 録画なし、所有sessionとdaemon終了 | recordingState=idle、close成功、daemon metadata/socket消失 |

## 画像・終了処理

製品CLIの`screenshot <absolute-path>`で取得したPNGを3枚とも開いて確認した。初期状態、環境値だけでのtap後、明示CLI上書きによるtap後を示す。環境値・エラー・queue契約は画像だけでは判定できないため、上記のtext/JSONと自動テストを併用する。

- `/tmp/mra-p2i8.hus6s0_l/evidence/01-environment-session-before.png`: Tap count: 0、入力はNot edited、Page 1。
- `/tmp/mra-p2i8.hus6s0_l/evidence/02-environment-session-after-tap.png`: Tap count: 1。
- `/tmp/mra-p2i8.hus6s0_l/evidence/03-cli-override-after-tap.png`: Tap count: 2。入力とPage 1は維持。

recordは開始していない。sessionをcloseし、daemon PID 72093とmetadata/socketの消失を確認した。runner（実行handle 46974、PID 71162）へ`q`を送りexit 0、PID消失を確認。割当端末のlaunchctlに`com.example.example`のentryがないことを確認し、同じUDIDだけをshutdown、状態Shutdownを再確認した。URIファイルを削除し、所有状態ファイルへteardown完了・releaseを記録した。共有allocation registryや別workerの資源は変更していない。

## 人間の再現手順

対象branchでexampleを新規起動するとTap count: 0へ戻る。現在使用可能であることを確認したSimulatorを使う。以下は今回の割当UDIDの例。ターミナルAでリポジトリルートから実行する。

```bash
umask 077
MRA_VERIFY_DIR=$(mktemp -d /tmp/mra-i8.XXXXXX)
echo "$MRA_VERIFY_DIR" # このpathだけをターミナルBへ引き継ぐ
xcrun simctl boot 022CF629-91E1-48F0-816B-2D86B8CD1D38
xcrun simctl bootstatus 022CF629-91E1-48F0-816B-2D86B8CD1D38 -b
cd example
flutter run -d 022CF629-91E1-48F0-816B-2D86B8CD1D38 --debug --no-pub \
  --vmservice-out-file="$MRA_VERIFY_DIR/vm-uri"
```

ターミナルBもリポジトリルートから開始する。`MRA_VERIFY_DIR`にはAのpathを指定する。URIを表示したりシェルトレースへ出力したりしない。

```bash
MRA_VERIFY_DIR='<ターミナルAのprivate directory>'
MRA_VERIFY_CLI="$PWD/packages/marionette_agent/bin/marionette_agent.dart"
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_VERIFY_DIR/runtime"
export MARIONETTE_AGENT_SESSION=p2-issue-8
export MARIONETTE_AGENT_TIMEOUT_MS=10000
MRA_VERIFY_URI=$(cat "$MRA_VERIFY_DIR/vm-uri")
dart "$MRA_VERIFY_CLI" connect "$MRA_VERIFY_URI" --json
dart "$MRA_VERIFY_CLI" snapshot
dart "$MRA_VERIFY_CLI" snapshot --json
dart "$MRA_VERIFY_CLI" tap --key tap_button --json
dart "$MRA_VERIFY_CLI" snapshot
dart "$MRA_VERIFY_CLI" screenshot "$MRA_VERIFY_DIR/after-env.png"
dart "$MRA_VERIFY_CLI" snapshot --session p2-issue-8-other --json
MARIONETTE_AGENT_TIMEOUT_MS=0 dart "$MRA_VERIFY_CLI" tap --key tap_button --json
dart "$MRA_VERIFY_CLI" snapshot --json
MARIONETTE_AGENT_SESSION='' MARIONETTE_AGENT_TIMEOUT_MS=invalid \
  dart "$MRA_VERIFY_CLI" tap --key tap_button --session p2-issue-8 --timeout 30000
dart "$MRA_VERIFY_CLI" snapshot --json
dart "$MRA_VERIFY_CLI" screenshot "$MRA_VERIFY_DIR/after-override.png"
dart "$MRA_VERIFY_CLI" close --json
```

期待結果: 初期0→環境指定tap後1、別sessionはNOT_CONNECTED、不正timeoutはINVALID_ARGUMENTでcount 1を維持、明示CLI上書き後2。PNGを開いて画面も確認する。ターミナルAで`q`を送りrunner/appの停止を確認し、使用したUDIDだけを`xcrun simctl shutdown <UDID>`で終了、URIファイルを削除する。queue期限は上記の環境テストで再現できる。

- [ ] 人間がPRの変更・手順・画面を確認した

統合時の注意: #12/#13のscreenshot変更を取り込んでいない。共通parser/helpと同じ仕様書への編集は競合候補となるため、developへの統合時に整合性を確認する。
