# Issue #6 — close --all 検証

担当: Issue #6 worker。branch: `feature/issue-6-close-all`。
基点: `50ccf97f47ecf03a51ea3c5646c9164325570c0b` (`origin/develop`)。
進捗: [todo.md](../../../../todo.md)。AgentのSimulator検証は成功。人間確認は未実施。

## 自動検証

`packages/marionette_agent` で `dart format .`、`dart analyze`、`dart test --concurrency=1 --reporter expanded` を実行。

`test/close_all_test.dart` はUnix socketを通して以下を検証する。

| 条件 | 期待結果 |
| --- | --- |
| 2 sessionにsnapshotを保持してclose --all | 名前順の成功Result、全observation/backend消失、socket・metadata削除、寿命lock再取得 |
| 一方のdisconnect失敗 | 他方は成功、CLOSE_FAILED/exit 1、session別error、秘匿済みtext表示 |
| 送信済みtapが停止、tapがqueue待ち、新規connect競合 | closeはTIMEOUT/exit 5、実行中はunknown、queueと新規connectはnot_sent、tap呼出しは1回だけ |
| closeより前に予約したconnect | 完了を待ち、成立した接続も破棄 |
| disconnectが完了しない | deadlineでunknown、socket・寿命lockを解放 |
| close応答を読まないclient | shutdownが有界に完了 |
| daemon不在・空 | session:null、closed:true、空sessions、繰り返し成功 |
| --session併用、重複flag、不正IPC params | INVALID_ARGUMENT、受付状態を変更しない |

初回の全体並列実行で短期限の新規競合テストが送信前に期限切れとなったため、順序をbarrierで保持したまま期限を1秒に拡大した。既存stdinテストもプロセス起動上限3秒に達した。同じhelperの`--version`は実測5.91秒（user 3.40秒、sys 0.33秒）。外側の起動待ちだけ15秒に拡大し、CLI要求期限150msとTIMEOUT/exit 5のassertionは維持した。

## Simulator環境と分離

- Flutter 3.47.2 / Dart 3.13.2、`marionette_flutter` / `marionette_mcp` 0.6.0。
- iOS 26.2: iPhone 17 (`DEDBBEE8-F70D-4CF2-A150-930585F683B0`)、iPhone 16e (`5C947B43-99AF-4EE5-BD88-F1946289FDD5`)。
- 両端末のShutdownを初回boot直前に再確認。他の端末は操作していない。
- 各appは専用worktreeの`example/`から1台ずつビルド。bundle ID: `com.example.example`。
- 私有root: `/tmp/mra-i6.ZgC39E`、runtime: `/tmp/mra-i6.ZgC39E/runtime`。
- session: `p1-issue-6`、`p1-issue-6-b`。URIとraw runnerログは私有root内、添付対象外。
- 自動実行スクリプト: `/private/tmp/mra-p1-20260912/worker-6-smoke.py`。
- CLI結果・実行コマンド: `/tmp/mra-i6.ZgC39E/evidence/results.json`（connect引数は秘匿）。

## 人間による再現

対象branchのexampleを2台の未使用Simulatorで新規起動し、各terminalでURIを新しい私有ファイルへ取得する。以下のroot変数は各terminalで同じ絶対pathを指定する。

```sh
# repo root、最初のterminalで作成
umask 077
VERIFY=$(mktemp -d /tmp/mra-i6-human.XXXXXX)
# それぞれ別terminalで同じVERIFYを設定してexample/へ移動
flutter run -d <A-UDID> --debug --no-pub --vmservice-out-file="$VERIFY/uri-a"
flutter run -d <B-UDID> --debug --no-pub --vmservice-out-file="$VERIFY/uri-b"
```

CLI用terminalでrepo rootへ移動し、同じVERIFYを設定する。シェルトレースは使わない。

```sh
export MARIONETTE_AGENT_RUNTIME_DIR="$VERIFY/runtime"
CLI=packages/marionette_agent/bin/marionette_agent.dart
dart "$CLI" --session p1-issue-6 connect "$(cat "$VERIFY/uri-a")"
dart "$CLI" --session p1-issue-6-b connect "$(cat "$VERIFY/uri-b")"
dart "$CLI" --session p1-issue-6 tap --key tap_button
dart "$CLI" --session p1-issue-6-b tap --key tap_button
dart "$CLI" --session p1-issue-6-b tap --key tap_button
dart "$CLI" --session p1-issue-6 snapshot
dart "$CLI" --session p1-issue-6-b snapshot
dart "$CLI" close --all --json
dart "$CLI" session list --json
dart "$CLI" --session p1-issue-6 snapshot --json
dart "$CLI" close --all --json
```

期待: 2件のclose成功、session listは空、snapshotはNOT_CONNECTED（exit 3）、再closeは空配列で成功。画面にはAのTap count 1とBのTap count 2が残り、アプリは終了しない。同じURIで明示connectとsnapshotを行い画面・観測が保持されることを確認する。もう一度接続した2 sessionを`close --all`（--jsonなし）で閉じ、同じ状態を確認する。古いrefを操作せず、新snapshotのrefを使う。

後始末: session/recordを閉じ、各Flutter runnerで`q`。所有アプリ停止を確認後、使用した端末をshutdownする。

- [ ] 人間が上記手順を確認した。

## Simulator実測結果（2026-09-12）

38回の製品CLI呼出しが期待終了コードと一致。JSON・text各形式で2 sessionを閉じ、続く一覧は空、snapshotはNOT_CONNECTED/exit 3、不在時の再closeは成功した。両形式ともmetadata/socket消失と別プロセスからの寿命lock取得を確認した。同じURIに再connectしたsnapshotの全要素（key/text/value）はclose前と一致。

| 証跡（全てview_imageで内容確認済み） | 期待／実際 |
| --- | --- |
| `/tmp/mra-i6.ZgC39E/evidence/json-after-close-a.png` | JSON close後もAのControls画面、Tap count 1、入力未編集・Page 1を保持 |
| `/tmp/mra-i6.ZgC39E/evidence/json-after-close-b.png` | JSON close後もBのControls画面、Tap count 2を保持 |
| `/tmp/mra-i6.ZgC39E/evidence/text-after-close-a.png` | text close後もAのControls画面、Tap count 2を保持 |
| `/tmp/mra-i6.ZgC39E/evidence/text-after-close-b.png` | text close後もBのControls画面、Tap count 4を保持 |

close後はCLI未接続なので、再connect前の画面を`xcrun simctl io <assigned-UDID> screenshot <absolute-path>`で取得した。画面取得後の明示connect/snapshotで同じアプリが応答し、カウンタを含む観測の一致も確認した。runner handles 64829/59024はqでexit 0、所有アプリの停止をlaunchctlで確認し、両端末をShutdownへ戻した。URIファイルは削除、raw runnerログは非公開。

代表的なJSON応答:

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": null,
  "data": {
    "closed": true,
    "sessions": [
      {
        "schemaVersion": 1,
        "ok": true,
        "session": "p1-issue-6",
        "data": {
          "closed": true
        },
        "error": null
      },
      {
        "schemaVersion": 1,
        "ok": true,
        "session": "p1-issue-6-b",
        "data": {
          "closed": true
        },
        "error": null
      }
    ]
  },
  "error": null
}
```

## 最終自動検証結果

- `dart format .`: 成功（69 files）。既存artifact_writer_test.dartに出た無関係な整形差分は採用しない。
- `dart analyze`: No issues found。
- `dart test --concurrency=1 --reporter expanded`: **171 tests passed**（87秒）。記録: `/private/tmp/mra-p1-20260912/worker-6-tests-final.log`。
- 最終help文言後の`dart test test/close_all_test.dart --reporter expanded`: 8 tests passed。`close --help`の--all説明も確認。
- `git diff --check`: 成功。実装対象外のexampleや上流依存への変更なし。
