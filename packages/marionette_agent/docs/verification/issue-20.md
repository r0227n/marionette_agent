# Issue #20 — ハイブリッドのヘッドレス実行と録画

検証日: 2026-09-16。Flutter testerとiOS / Android / macOS / Webの各実行環境をCLIで明示選択し、ウィンドウを表示せず起動・操作・録画・終了できることを確認した。人間による再確認は未実施。

## 実装範囲

- `launch <project> --platform tester|ios|android|macos|web`でdebugアプリを起動し、VM Service接続と最初のMarionette観測まで行う。
- `marionette_agent_util/src/application`がplatform別起動、SDK探索、project排他、private URI取得、所有プロセス・端末の終了を担当。`marionette_agent`はutilを呼び出し、CLI構文・policy・session・既存backend接続を担当する。
- `record start <new.mp4> --platform flutter [--fps 1..60]`で単一Flutter viewを録画。取得時刻を保った無音H.264 VFR MP4へ保存し、重複stop・既存出力保護・close時保存を扱う。
- launchしたsessionのcloseは録画を確定後に所有アプリと端末を終了する。手動起動へのconnectはアプリを終了しない。自動fallback・UI操作の再送は行わない。
- macOS exampleはNSWindowを非表示にし、debug opt-inの`enableHeadlessRendering()`で描画を維持する。一般アプリには同等のアプリ側対応が必要。

## 対象コード・環境

- branch: `feature/issue-20-headless-feasibility`。基点`d890003afa8f5d99e765324416a539371ebbc0c8`からの本PR差分を検証。検証commitはPR本文に記載する。
- macOS 26.5.2 arm64、Xcode 26.3、Flutter 3.47.2、Dart 3.13.2、Marionette 0.6.0、ffmpeg/ffprobe 9.0.1。
- tester: Flutterのテスト用エンジン。論理800×600、DPR 3。OS／ブラウザーの模倣ではない。
- iOS: iOS 26.2 / iPhone Air。utilが専用device setに作成したMarionette-Headless、UDID `54D260F1-E9DD-41F9-BC7C-1C1B03073DA2`。
- Android: Android 16 / Pixel 9 Pro、検証用の一時AVD `mra20_hybrid`、`emulator-5586`。utilが`-no-window -no-audio -no-snapshot -read-only`で新規起動。
- macOS: native FlutterEngine、非表示NSWindow、環境変数とDart defineによる明示opt-in。
- Web: Chrome 152.0.7977.83、Flutterの`--web-run-headless`、専用profile。

## 非表示と終了の確認

CoreGraphicsのon-screen window一覧を実行中の所有PID／デバイス名で照合し、testerのrunner、iOSの専用デバイス、macOSアプリ、Chromeの表示ウィンドウ0件を確認した。Androidは所有Emulatorの`-no-window`と表示ウィンドウ0件を確認した。macOSアプリPID 11181、Android Emulator PID 15554、iOS runner PID 13153を記録した。

通常device setでのSimulator.appの自動表示を避けるため、iOSは専用device setを使用する。macOSホストのログイン済みGUIセッションは必要。

close後の所有プロセスの消滅と、iOSデバイス・private起動領域の回収を確認した。共有のSimulator、既存AVD本体、adb serverには終了要求を送っていない。

## 操作と動画

5環境で製品CLIのrecord smokeを実行。各19呼出しは、18成功と、既存出力へのstartが期待どおりIO_ERROR（exit 1）。launch→録画開始→タブ往復→snapshot/PNG→tap→fill→snapshot/PNG→status→stop→重複stop→既存出力拒否→新規録画→close保存まで確認した。

見る場所はTapカードのカウンタとFillカードの文字数。すべてカウンタ0→1、Not edited→19 charactersを確認した。operations動画の先頭・途中・最後とclose動画のフレームを開き、PNG・CLI snapshotと照合した。

| 環境 | 指定fps | 動画寸法 | 再生時間 | フレーム数 | 平均fps | PR添付名 |
| --- | --- | --- | --- | --- | --- | --- |
| tester | 10 | 2000×1500 | 16.434245秒 | 83 | 5.05 | `hybrid-tester-operations.mp4` |
| ios | 10 | 922×2000 | 21.298343秒 | 131 | 6.15 | `hybrid-ios-operations.mp4` |
| android | 2 | 896×2000 | 20.621432秒 | 27 | 1.31 | `hybrid-android-operations.mp4` |
| macos | 10 | 1600×1200 | 16.165808秒 | 92 | 5.69 | `hybrid-macos-operations.mp4` |
| web | 10 | 2000×1380 | 18.319036秒 | 39 | 2.13 | `hybrid-web-operations.mp4` |

上記5本と各環境の`hybrid-<platform>-close.mp4`を添付する。合計10動画を全編デコードしexit 0・stderr空を確認。全フレームのPTSが単調増加し、最終PTS+durationとMP4のdurationが3µs以内で一致した。速度変更・フレーム補間・画面の再描画はしていない。指定fpsは取得間隔であり、そのフレームレートの達成を保証しない。

## testerのworkflow

別の19 CLI呼出しでJSON／YAMLの7 step workflowを確認した。[headless-controls.json](../../examples/workflows/headless-controls.json)と[YAML版](../../examples/workflows/headless-controls.yaml)は同じシナリオで、Controlsへの切替後に200px上へscrollし、500px左へswipeする。

両形式とも最終snapshotでCurrent page: 2を確認。最終refを別CLIのfillへ渡して13 charactersを確認し、古いrefはSTALE_REF（exit 4）として拒否された。さらにscrollでBottom reachedへ移動し、Add log entryをtap、logsのmanual log entry addedとPNGを確認した。元の300pxシナリオを全viewportに適用する変更はしていない。

## 自動テスト

- CLI: format・静的解析成功。全314テスト成功（3分29秒）。
- util: format・静的解析成功、全52テスト成功。実ffmpeg/ffprobeも実行しskipなし。
- Flutter補助パッケージ: 静的解析成功、全8テスト成功。
- example: 静的解析成功、全6テスト成功。
- 合計380テスト。utilの実fixture processでproject排他、起動失敗、deadline、起動中dispose、プロセス終了、Webの起動通知待ち、Android shell準備待ちを確認。CLIではpolicy・初期接続失敗・外部接続の非所有・異常終了・close all・終了失敗時の接続解放を確認した。

## 起動時に確認した差と制限

WebはURIが出力されてもアプリ初期化が終わっていない場合がある。Flutterのdebuggerと同様に、utilで該当appのmachine `app.started`を待ってから接続へ進むよう修正した。URIを先に書くfixtureで修正前の失敗と修正後の成功を確認した。

Androidはadbがdeviceを列挙した直後にshellがまだ使えない場合がある。utilは起動中の読み取り確認だけをpollし、UI操作やinstallを自動再送しない。初回AVDのuserdata作成ではホスト容量不足も観測したため、一時AVDへ既存の初期化済みuserdataをAPFS cloneし、読み取り専用で検証した。利用者のAVD本体は変更していない。

ホストスリープ、WindowServerのないホスト、Linux／Windows、iOS／Android実機、OSキーボード・ダイアログ・ブラウザーUI・platform viewの収録、高速アニメーションの全フレーム取得は検証対象外。macOSの一般アプリの非表示化はアプリ側対応を要する。

## 再現

[日本語ヘッドレスガイド](../../../../docs/ja/headless.ja.md)に5環境の選択・起動・録画・終了とworkflowをまとめた。毎回新しいprivate runtime／session／出力先を用意し、選択するSDK・Simulator type/runtime・既存AVD・未使用portを準備する。管理起動ではURIを手動取得せず、launchに任せる。Androidの録画確認は`--fps 2`を指定した。

record smokeは`MARIONETTE_LAUNCH_OPTIONS`にprojectとlaunch引数のJSON配列を指定し、`MARIONETTE_RECORD_PLATFORM=flutter`で同じ検証を実行できる。生ログと認証URIをPRへ掲載しない。
