# Issue #3 検証記録

- Issue: https://github.com/r0227n/marionette_agent/issues/3
- 担当branch: `feature/issue-3-standalone-wait`
- 検証対象code commit: `69a57e543dba93c51ed5591bda0a04ed1df51fa8`
- 検証日: 2026-09-11 (Asia/Tokyo)
- 進捗記録: `AGENTS.md`は`todo.md`を指定していないため、issues-to-pr worker既定のこのfileを使用した。

## 環境

- host: macOS 26.5.2 (25F84)
- Flutter 3.47.2 stable / Dart 3.13.2
- `marionette_agent` 0.0.1
- `marionette_mcp` 0.6.0 / `marionette_flutter` 0.6.0
- iPhone 17 / iOS 26.2 / UDID `DEDBBEE8-F70D-4CF2-A150-930585F683B0`
- session: `issue3`
- 実行ごとに短いprivate directoryを作成し、全製品CLI呼出しへ同じmode 0700の`MARIONETTE_AGENT_RUNTIME_DIR`を指定した。VM Service URIとraw runner logは非公開領域だけで扱い、検証後に削除した。

## 自動検証

`packages/marionette_agent`で実行した。

| コマンド | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `dart format .` | package全体をformatできる | 成功 |
| `dart analyze` | issueなし | `No issues found!` |
| `dart test` | 全test成功 | 146 tests passed |
| `dart test test/wait_test.dart test/workflow_execution_test.dart test/workflow_cli_test.dart` | wait、workflow、IPCの関連testが成功 | 36 tests passed |

`wait_test.dart`と`workflow_cli_test.dart`で次を確認した。

- 単独waitとworkflow waitが、0→1件、1→0件、`visible:false`／`null`、複数一致、由来未確認textについて同じ結果になる。
- ref、座標、selector 0件／複数、不正state、50〜1,000ms外または非整数のpoll間隔をCLIとdaemon境界で拒否する。
- 成功waitは公開snapshot／refを更新せず既存refを維持する。wait timeout／通信断は`outcome:not_sent`で接続世代とrefを破棄し、queue開始前のtimeoutは観測せず接続を維持する。
- wait中のbackend callは`inspect`だけで、tap／fill／swipeの送信回数は0。workflowと単独コマンドは同じ登録済みhandlerを通る。
- 固定bindingで未対応のidentifierは観測前に`UNSUPPORTED_CAPABILITY`となる。

## iOS Simulator検証

### 準備

`flutter run`は起動中のまま保持するため、runner用とCLI用の2つのterminalを使う。URI値は表示・検証記録へ保存しない。以下の端末は検証時の割当であり、人間が再現するときは使用する端末のUDIDへ置き換える。

ターミナルAをこのworktreeの`example/`で開き、次を実行する。表示するのは私有ディレクトリのpathだけであり、ターミナルBへその値を引き継ぐ。

```bash
umask 077
MRA_I3_CHECK=$(mktemp -d /tmp/mra-i3.XXXXXX)
printf '%s\n' "$MRA_I3_CHECK"
MRA_VERIFY_URI_FILE="$MRA_I3_CHECK/uri"
SIMULATOR_UDID=DEDBBEE8-F70D-4CF2-A150-930585F683B0
flutter pub get
flutter run -d "$SIMULATOR_UDID" --debug --no-pub \
  --vmservice-out-file="$MRA_VERIFY_URI_FILE" \
  >"$MRA_I3_CHECK/runner.log" 2>&1
```

アプリ起動後、ターミナルBを同じworktreeのルートで開く。`MRA_I3_CHECK`にはターミナルAで表示された実際の絶対pathを設定し、新しいディレクトリを作り直さない。

```bash
MRA_I3_CHECK=/tmp/mra-i3.XXXXXX  # ターミナルAで表示されたpathへ置換
export MARIONETTE_AGENT_RUNTIME_DIR="$MRA_I3_CHECK/runtime"
MRA_VERIFY_URI_FILE="$MRA_I3_CHECK/uri"
CLI="$PWD/packages/marionette_agent/bin/marionette_agent.dart"
SESSION=issue3
VM_URI=$(cat "$MRA_VERIFY_URI_FILE")
dart "$CLI" --session "$SESSION" connect "$VM_URI" --json
```

以下の操作もターミナルBで実行する。確認後はCLIでsessionをcloseし、ターミナルAのrunnerを`q`で終了してアプリの停止を確認する。URIとraw runner logを削除し、選択したエビデンスは保持する。

### 操作と観測

| 手順／コマンド | 期待結果 | 実際の結果 |
| --- | --- | --- |
| `snapshot --json` | 初期Controlsで`operation_scroll_area`が存在し、`about_content`が存在しない | generation 1に`operation_scroll_area` (`visible:true`)を確認。`about_content`なし |
| `screenshot <before.png> --json` | Controls画面を保存 | 919×2000 PNGを保存し、目視でControls、Tap count 0、Not edited、Page 1を確認 |
| `record start <transitions.mp4> --platform ios --device "$SIMULATOR_UDID" --json` | 割当Simulatorの録画開始 | `recordingState:"recording"` |
| `tap --key about_tab --json` | Aboutへ遷移を開始 | 成功、`requiresSnapshot:true` |
| `wait --key about_content --poll-interval 50 --timeout 5000` | text形式で出現待ちが成功 | exit 0、`state: exists`、`requiresSnapshot: true` |
| `wait --key operation_scroll_area --state gone --poll-interval 50 --timeout 5000 --json` | JSON形式で消失待ちが成功 | `ok:true`、`state:"gone"`、`requiresSnapshot:true` |
| `snapshot --json` | Aboutだけが観測される | generation 2に`about_content` (`visible:true`)を確認し、`operation_scroll_area`なし |
| `screenshot <about.png> --json` | About画面を保存 | 919×2000 PNGを保存し、中央のWorkflow fixtureを目視確認 |
| `tap --key controls_tab --json` | Controlsへ戻る | 成功、`requiresSnapshot:true` |
| `wait --key operation_scroll_area --poll-interval 50 --timeout 5000 --json` | JSON形式で出現待ちが成功 | `ok:true`、`state:"exists"`、`requiresSnapshot:true` |
| `wait --key about_content --state gone --poll-interval 50 --timeout 5000` | text形式で消失待ちが成功 | exit 0、`state: gone`、`requiresSnapshot: true` |
| `snapshot --json` | Controlsだけが観測される | generation 3に`operation_scroll_area` (`visible:true`)を確認し、`about_content`なし |
| `screenshot <restored.png> --json` | Controls復帰を保存 | 初期Controls PNGと同一SHA-256であることを確認 |
| `record stop --json` | 動画を確定 | `recordingState:"stopped"`、207,688 bytes |

## エビデンス

全候補を画像表示または動画の時系列frameで目視し、単なる存在・size確認にはしていない。

| file | 内容 | 検査結果 |
| --- | --- | --- |
| `issue-3-before.png` | wait前のControls | 919×2000 PNG、SHA-256 `4fdde0463375482bb9d203c3089562f37ab7abb06a019303d437d2646bdd6e0e` |
| `issue-3-about.png` | `exists`／`gone`成功後のAbout | 919×2000 PNG、SHA-256 `8327ba0154de042e5935bd816c515d99cd22da1b0af14013fffb8503d4cdeb0f` |
| `issue-3-restored.png` | 逆方向の`exists`／`gone`成功後 | 初期PNGと同一SHA-256。重複画像のためPR添付候補から除外 |
| `issue-3-wait-transitions.mp4` | ControlsからAboutへの遷移 | H.264、1206×2622、36.945秒、207,688 bytes。開始／遷移後frameを復号・目視。SHA-256 `c7885805ff39a1a3f6caa207b93744478837be134a57bf192ac6edb3e6610e9e` |

PRには重複でない`issue-3-before.png`、`issue-3-about.png`、`issue-3-wait-transitions.mp4`を添付する。

## 人間による再現手順

1. このbranchをcheckoutし、利用するiOS Simulatorを起動する。
2. 上記の準備手順でprivate URI fileと新しい短い`MARIONETTE_AGENT_RUNTIME_DIR`を作り、このworktreeの`example/`をdebug起動する。
3. このworktreeの`packages/marionette_agent/bin/marionette_agent.dart`から接続し、初期`snapshot`で`operation_scroll_area`があることを確認する。
4. `tap --key about_tab`後、`wait --key about_content --timeout 5000`と`wait --key operation_scroll_area --state gone --timeout 5000 --json`を実行する。両方がexit 0になり、後続`snapshot`で`about_content`だけが存在することを確認する。
5. `tap --key controls_tab`後、逆のexists／gone waitを実行し、後続`snapshot`と画面が初期Controlsへ戻ったことを確認する。
6. `close`でsessionを閉じ、Flutter runnerとアプリを終了する。

人間による確認は未実施であり、Draft PRのcheckboxは未チェックのままにする。

## 制約

- Simulator fixtureで直接確認したselectorは`key`。不可視、複数一致、由来未確認text、timeout、通信断、queue待ちは決定的なFakeBackend／IPC testで確認した。
- `identifier`は固定binding 0.6.0の既知の未対応機能であり、従来どおり`UNSUPPORTED_CAPABILITY`となる。
- Web向けwait、substring検索、`wait <ms>`、workflow制御構文はIssue #3の対象外。

## 終了処理

recordを確定し、`issue3` sessionと専用daemonをcloseし、Flutter runner／アプリを終了した。private URIとraw runner logを削除し、割当Simulatorだけを`Shutdown`へ戻した。PR添付候補はprivate verification directoryに保持した。
