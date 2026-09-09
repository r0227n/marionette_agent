# 開発進捗

## R02: 録画方式の再比較

- 状態: 完了
- 担当モデル: GPT-6 (Codex)
- 依存: R01の実装とexample。iOS Simulatorで仮想キーボード表示を確認し、simctlとmarionette_mcpの動画を比較する。
- 完了条件: 同じ画面操作を両方式で録画・復号・目視確認し、実装判断と証跡をPR #19のコメントへ追加する。
- 結果: [比較記録](docs/recording-comparison.md)。simctlは仮想キーボードと変換候補を収録、上流record-videoは同領域が空白。入力結果は両方に映る。製品CLIのrecord_smokeも再成功し、仮想キーボードを含む動画を確認。現在のOS録画方式を維持する。
- 証跡: [PR #19コメント](https://github.com/r0227n/marionette_agent/pull/19#issuecomment-5605923365)へ動画3本と抽出PNG2枚を投稿。
- 制約: 同時録画のsimctl原本はffmpeg null muxerでDTS警告3件。画像復号は成功、根因は未確定。製品CLI単独録画2本と上流動画の全フレーム復号は警告なし。性能比較・OSダイアログ・PlatformViewは未実測。R01のmacOS保留は継続。
- 変更は本記録と比較文書のみ。git diff --checkとリンク・仕様整合性を確認。

## R01: プラットフォーム処理の内部パッケージとrecord

- 状態: 作業中
- 担当モデル: GPT-6 (Codex)
- 依存: 既存session/daemon/CLI。録画中のdaemon寿命・接続なし録画・期限処理のため基盤を拡張する。
- 利用者の指示により `packages/marionette_agent_util` を新設。録画専用ではなく、CLIからOS固有処理を分離する内部パッケージとする。
- 完了条件: iOS Simulator / Android Emulator / macOSのrecord start・status・stopを製品CLIから検証。動画を復号し画面変化を確認。format/analyze/全test、SPEC/ARCHITECTURE/日本語CLI参照更新。
- worktree: feature/device-recording。hook_status=skipped-untrusted。既知の依存取得を個別実行する。
- macOS: CGPreflightScreenCaptureAccess=false。画面収録権限の有効化を利用者へ依頼済み。

- macOS: 許可変更後にCGPreflightScreenCaptureAccess=trueを確認。ただし利用者から再起動のため検証保留の指示あり。以降macOS実録画は実施せず、未完了として引き継ぐ。

### 実装結果

- `packages/marionette_agent_util`に共通PlatformException、終了通知、録画API、OS別backend、端末排他・保存・終了処理を追加。録画専用ではなく内部プラットフォームサービスとする。
- CLIにrecord start/status/stopを追加。接続なしの録画session、close時の確定、VM Service切断との独立、IPC v3、既存file/symlink拒否を実装。
- Web/Linux/WindowsはutilでUNSUPPORTED_CAPABILITYをthrowし、CLIはdaemon起動前に終了コード6を返す。
- SPEC、ARCHITECTURE、日本語CLI参照、コマンド／workflowのIPC版説明を更新。
- 内部path依存により両パッケージをpublish_to:noneとした。配布は同一repoのcheckoutかコンパイル済みCLIを用いる。

### 自動検証

- `packages/marionette_agent`: `dart format lib test/record_test.dart integration_test/record_smoke.dart`、`dart analyze`成功。`dart test`は131件すべて成功（終了通知分離後にも実行）。ログ: `/tmp/mra-record-agent-tests.log`。
- `packages/marionette_agent_util`: `dart format lib test`、`dart analyze`成功。`dart test`は8件すべて成功。
- `git diff --check`: 成功。
- 実CLIで`record start /tmp/unsupported.mp4 --platform web|linux|windows --device 1 --json`をそれぞれ実行。期待／実際: 終了コード6、UNSUPPORTED_CAPABILITY。専用runtime directoryが作成されないことも確認。

### iOS Simulator / Android Emulator 実環境検証

ホストmacOS 26.5.2。exampleはFlutter 3.47.2／marionette_flutter 0.6.0。iOSはiPhone 17 Pro、iOS 26.2、UDID `022CF629-91E1-48F0-816B-2D86B8CD1D38`。AndroidはPixel_9_Pro AVD、adb serial `emulator-5556`。

example内で`flutter pub get`後、次のコマンドで起動（VM Service URIの値は記録しない）。

```sh
flutter run -d 022CF629-91E1-48F0-816B-2D86B8CD1D38 --debug --no-pub --vmservice-out-file=/tmp/mra-record-ios-uri
flutter run -d emulator-5556 --debug --no-pub --vmservice-out-file=/tmp/mra-record-android-uri
```

packages/marionette_agent内で実行:

```sh
MARIONETTE_RECORD_PLATFORM=ios MARIONETTE_RECORD_DEVICE=022CF629-91E1-48F0-816B-2D86B8CD1D38 MARIONETTE_TEST_VM_URI_FILE=/tmp/mra-record-ios-uri MARIONETTE_RECORD_EVIDENCE=/tmp/mra-record-evidence-ios-final dart run integration_test/record_smoke.dart
MARIONETTE_RECORD_PLATFORM=android MARIONETTE_RECORD_DEVICE=emulator-5556 MARIONETTE_TEST_VM_URI_FILE=/tmp/mra-record-android-uri MARIONETTE_RECORD_EVIDENCE=/tmp/mra-record-evidence-android-final dart run integration_test/record_smoke.dart
```

期待: 接続なしrecord start→connect→タブ往復→snapshot→tap→入力欄tap→fill→snapshot→record status→stop→重複stop→既存動画拒否→新規record→closeで動画確定。
実際: 両環境で全工程成功。Tap countは2→3、Not edited→19 charactersへ変化。UIのsnapshotに加えて動画のフレームでも確認した。Androidの端末動画にはソフトウェアキーボードが含まれ、Flutter screenshotには含まれない。iOSの録画にはOSのステータスバーが含まれる（このSimulatorのソフトウェアキーボードは非表示）。

| 動画 | codec / 解像度 | duration | bytes |
| --- | --- | --- | --- |
| iOS operations.mp4 | H.264 / 1206×2622 | 18.101667s | 2106463 |
| iOS close.mp4 | H.264 / 1206×2622 | 2.233333s | 382279 |
| Android operations.mp4 | H.264 / 720×1280 | 18.656911s | 313550 |
| Android close.mp4 | H.264 / 720×1280 | 2.553367s | 48784 |

ffprobeで動画情報を確認し、全動画を`ffmpeg -v error -i <video> -map 0:v:0 -enc_time_base:v demux -fps_mode passthrough -f null -`で全フレーム復号。期待／実際: 終了コード0、stderrなし。確認用フレームも抽出して画面変化とキーボードを目視確認した。

追加で専用runtimeのCLIからiOS録画を開始し、そのdaemonのmetadataと実行コマンドを照合したPIDへSIGTERMを送信。期待／実際: 動画確定とmetadata除去成功。動画はH.264 / 1206×2622 / 1.036667s / 193674bytes、全フレーム復号成功。証跡: `/tmp/mra-record-evidence-signal/`。

PR用証跡: `/tmp/mra-record-pr-evidence/`（動画5本、操作前後のPNG4枚）。結果JSONと元動画は各evidence directoryに保持する。

### 残る作業・制約

- macOS実録画検証: 利用者の指示で保留。許可確認APIがfalse→trueになったことは確認したが、製品record CLIによるmacOS動画の生成・再生は未確認。タスク全体は未完了のまま。
- Android実機、iOS実機、Android180秒自動停止の実環境検証は未実施。自動終了経路は単体テストで確認。iOS実機は未対応。
- macOS標準コマンドにはfirst-frame通知がなく、開始は起動後1秒の生存確認。stopで生成動画を検証する。
- 音声、回転中の正しい収録、SIGKILL／ホスト停止後の復元、録画分割結合は対象外。
- 後続Issue作成・本文とfeatureラベルの読み戻し確認済み: Web #16、Linux #17、Windows #18。
