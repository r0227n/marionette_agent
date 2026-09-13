# Issue #4: get observations

- 担当: Issue #4 sole worker (gpt-6-astra, medium requested).
- Branch: `feature/issue-4-get-observations`.
- Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b`.
- 検証済みコードcommit: `6010ee567ff0af4ddb04586b7fde166a8f1f7462`。後続変更はこの検証記録と進捗indexのみ。
- 進捗場所確認: AGENTS.mdと既存記録を確認。todo.mdは存在しなかったためrootに担当・検証結果のindexを整備し、詳細は現行worker規約のIssue別記録へ残した。
- 実装: get text/boxのread resolver、get countの独立候補集計、CLI/help、SPEC・ARCHITECTURE・日本語reference。
- 自動検証: `dart format .`成功、`dart analyze`はNo issues found、`dart test`は171件全成功（39秒）。新規unit/IPCは8テスト。初回の新規テスト2件は不正ref構文を修正。既存FIFO/stdinの3秒process起動テストがホスト負荷下でtimeoutしたが、Simulator終了後の最終全体runは同じテストを含め全成功。最終ログ: `/tmp/mra-i4.0ruBiq/dart-test-final.log`。formatが変更した無関係な既存テストの空白差分は元へ戻した。
- Simulator: 予約UDID `022CF629-91E1-48F0-816B-2D86B8CD1D38`、iPhone 17 Pro / iOS 26.2。起動直前の状態はShutdown。
- 人間確認: 未実施。

## Simulator実績

2026-09-12、Flutter 3.47.2 / marionette_flutter 0.6.0。割当worktreeのexampleをdebug起動し、同worktreeのDart CLIを別processとして29回呼び出した。runtimeは`/tmp/mra-i4.0ruBiq/runtime`、sessionは`p1-issue-4`。実行時の製品コードはこの変更のcommit前diff（後記commitと同内容）。URIとraw runner logは私有ディレクトリへ分離した。

| コマンド（text/JSON両形式） | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `get text @e4` | snapshotのtap_resultと一致 | `{"text":"Tap count: 0"}` |
| `get text --key tap_button`（追加確認） | snapshotでtext欠損 | text/JSONとも`{"text":null}`、exit 0 |
| `get box @e3` | snapshotのtap_button.boundsと一致 | x=32, y=186, width=97.3416976928711, height=48、unit=flutter_logical_pixels |
| `get count --key missing-issue-4` | 0件成功 | count=0、exit 0 |
| `get count --key tap_button` | 1件成功 | count=1、exit 0 |
| `get count --type Text` | snapshotのText件数と一致、複数成功 | count=9、exit 0 |
| `get text --key missing-issue-4` | 対象なし | TARGET_NOT_FOUND、exit 4、not_sent |
| `get box --type Text` | 一意性エラー | AMBIGUOUS_TARGET、exit 4、not_sent |
| `get count @e3` | ref拒否 | INVALID_ARGUMENT、exit 2、not_sent |
| `get count --identifier tap_button` | 未対応 | UNSUPPORTED_CAPABILITY、exit 6、not_sent |
| `tap @e3`（上記get後、再snapshotなし） | 同じrefで1回操作できる | exit 0、Tap count: 1 |
| 操作後の`get text @e4` / `get box @e3` | 操作による失効 | STALE_REF、exit 4、not_sent |

`before.png`をview_imageで開き、Tap count: 0、空の入力欄、Page 1を確認。`after.png`も開き、Tap count: 1へだけ変化し、入力欄とページが維持されたことを確認した。boxの論理座標はsnapshot値と比較し、画像pixelとの換算は行っていない。

証跡: `/tmp/mra-i4.0ruBiq/evidence/results.json`（29呼出しのコマンド・形式・exit・stdout）、同ディレクトリの`before.png` / `after.png`。欠損text/bounds、空文字、実際のゼロ、属性変更stale、未知型text衝突は`test/get_test.dart`のunit/IPCで確認する。

追加の実機欠損text確認は`null-text.txt` / `null-json.json`へ保存。終了時はsession close成功、daemon PID 70974とrunner PID 60687の消滅、socket/metadata削除、所有bundle `com.example.example`のterminate、割当SimulatorのShutdownを確認。URIファイルも削除した。raw runner logは公開しない。

## 人間の再現手順

1. このbranchのworktreeで、使用可能か確認したSimulatorを割り当てる。exampleを停止して新規起動し、Tap count: 0へ戻す。
2. 以下の私有pathを同じ値で各terminalへ引き継ぐ。runnerログやURIは共有しない。

```sh
umask 077
MRA_I4_DIR=$(mktemp -d /tmp/mra-i4.XXXXXX)
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_I4_DIR/runtime"
cd example
flutter pub get
flutter run -d <ASSIGNED_UDID> --debug --no-pub \
  --vmservice-out-file="$MRA_I4_DIR/vm-uri" > "$MRA_I4_DIR/runner.log" 2>&1
```

3. 別terminalで同じ`MRA_I4_DIR`とruntimeを設定し、repo rootからpackageへ移動して再現スクリプトを実行する。

```sh
cd packages/marionette_agent
MARIONETTE_TEST_VM_URI_FILE="$MRA_I4_DIR/vm-uri" \
MARIONETTE_TEST_EVIDENCE="$MRA_I4_DIR/evidence" \
dart run integration_test/get_smoke.dart
```

4. 29呼出しの成功表示と結果記録を確認し、before/after画像を開いて上表と照合する。ref番号はsnapshotの実際の値を使う。
5. スクリプトのclose後にdaemon終了を確認し、runnerへqを送り終了。所有bundleのみ停止し、割当Simulatorをshutdownする。

- [ ] 人間が上記を再現し、変更内容と画面を確認した

## PR #27 integration review (2026-09-13)

Merged develop through PR #26 and unified get/is read resolution. dart format, dart analyze and all 184 tests passed. On iPhone 17 Pro / iOS 26.2 (022CF629-91E1-48F0-816B-2D86B8CD1D38), the existing get_smoke.dart passed all 29 CLI calls; before/after images were opened and showed count 0 → 1. Additional is visible → get text → tap using the same ref → get text confirmed count 1 → 2. Evidence: `/tmp/mra-review27.8031lav_/evidence`. Sessions/daemon and owned app/runner stopped; Simulator shut down. Reproduce using the existing get smoke instructions above, then query is visible before tapping a fresh snapshot ref.
