# Issue #20 — 各実行環境のヘッドレス録画

検証日: 2026-09-16。iOS / Android / macOS / Webそれぞれの実行環境で、ウィンドウを表示せず操作・録画・動画確定を確認した。人間による再確認は未実施。

## 実装範囲

- 接続済みsessionに`record start <new.mp4> --platform flutter [--fps 1..60]`を追加。`--device`は省略する。
- 録画専用の読み取りVM接続からPNGを取得し、実取得時刻を保った無音H.264 VFR MP4へ保存。stop、重複stop、close時保存、既存出力保護を共通契約で扱う。
- macOS exampleはnative windowを非表示で起動する。debug opt-inの`enableHeadlessRendering()`はOSのライフサイクル通知を変更せず、非表示時のフレーム生成を維持する。
- レビューで再現した2件を修正。標準AppLifecycleListenerとの併用・非表示からの復帰をwidgetテストで確認し、破損PNGを実ffmpegでIO_ERRORとして検出して部分動画を公開しない回帰テストを追加した。
- 対象は利用者が追加指定した「各プラットフォームの実行環境」。アプリ・OSの起動と終了は呼出元が管理する。Flutter tester方式の初期調査は[別文書](../../../../docs/headless-feasibility-issue-20.md)を参照。

## 対象コード・環境

- branch: `feature/issue-20-headless-feasibility`。基点`d890003afa8f5d99e765324416a539371ebbc0c8`からの本PR差分を検証。検証commitはPR本文に記載する。
- macOS 26.5.2 arm64、Xcode 26.3、Flutter 3.47.2、Dart 3.13.2、Marionette 0.6.0、ffmpeg/ffprobe 9.0.1。
- iOS: iOS 26.2 / iPhone Air。専用device setのMRA20-PR、UDID `DEED193A-1AB7-4FAC-A4A7-C7E197FD753F`を作成して使用した。
- Android: Android 16 / Pixel 9 Pro、専用の一時AVD `mra20_pr`、`emulator-5584`。`-no-window -no-audio -no-snapshot-save`で起動。
- macOS: native FlutterEngine、`MARIONETTE_HEADLESS=1`と`--dart-define=MARIONETTE_HEADLESS=true`。
- Web: Chrome 152.0.7977.83、Flutterの`--web-run-headless`、専用profile。

## 非表示の確認

CoreGraphicsのon-screen window一覧を対象PID／デバイス名で照合した。macOSアプリPID 63529とChrome PID 65251はいずれも表示ウィンドウ0件。iOSのMRA20-PRウィンドウも0件で、Simulatorウィンドウ名を取得できる状態を確認した。Androidは専用AVDの所有PID 71892で`-no-window`を確認した。

既定のiOS device setではSimulator.appがbootを検知して表示する場合があるため、専用device setを使用する。macOSホストのログイン済みGUIセッションは必要。

## 操作と動画

4環境で製品CLIのrecord smokeを実行。各19呼出しは、18成功と、既存出力へのstartが期待どおりIO_ERROR（exit 1）。接続→録画開始→タブ往復→snapshot/PNG→tap→fill→snapshot/PNG→status→stop→重複stop→既存出力拒否→新規録画→close保存まで確認した。

見る場所はTapカードのカウンタとFillカードの文字数。iOSは0→1、Androidは4→5、macOS/Webは1→2。タブ往復で入力欄がNot editedに戻り、fill後に19 charactersとなる。動画の先頭・途中・最後のフレーム、close動画、CLI snapshotを照合した。録画の冒頭には前回の入力が残っている場合があり、タブ往復後の初期状態と比較する。

| 環境 | 指定fps | 動画寸法 | 再生時間 | フレーム数 | 平均fps | PR添付名 |
| --- | --- | --- | --- | --- | --- | --- |
| iOS | 10 | 922×2000 | 15.162854秒 | 96 | 6.33 | `headless-ios-operations.mp4` |
| Android | 2 | 896×2000 | 18.553680秒 | 29 | 1.56 | `headless-android-operations.mp4` |
| macOS | 10 | 1600×1200 | 18.479729秒 | 34 | 1.84 | `headless-macos-operations.mp4` |
| Web | 10 | 2000×1380 | 18.782472秒 | 37 | 1.97 | `headless-web-operations.mp4` |

上記4本に加え、各環境の`headless-<platform>-close.mp4`を添付する。合計8動画を全編デコードしてexit 0・stderr空を確認。全フレームのPTSが単調増加し、最後の表示時間が正で、最終PTS+durationとMP4のdurationが3µs以内で一致した。速度変更・フレーム補間・画面の再描画はしていない。指定fpsは取得間隔であり、そのフレームレートの達成を保証しない。

## 自動テスト

- CLI: format・静的解析成功。全305テスト成功（3分24秒）。
- util: 静的解析成功、全43テスト成功。実ffmpeg/ffprobeのテストも実行し、skipなし。
- Flutter補助パッケージ: 静的解析成功、全8テスト成功。
- example: 静的解析成功、全6テスト成功。
- 4パッケージ合計362テスト成功。対象コードのformatを適用。文書のローカルリンク64件、shell記載6件、差分の空白も確認した。

## 検証中に観測した環境上の制約

ホストのSleep/DarkWake反復中に録画の取得期限・接続確認とCLIテストが失敗した。電源ログとテストの長い中断時刻を照合し、ホストを起動状態に保って全体テストをやり直した。録画中のホストスリープは対応範囲外。Androidの最終確認は`--fps 2`で2回連続成功したが、fps低下だけが安定性の原因とは判定していない。

既存Android AVDは空き容量不足でインストールできなかったため、専用の一時AVDを作成した。CLIテストの再実行時にもホスト側の容量不足を観測し、今回の再生成可能なビルド出力を整理した。

OSキーボード・ダイアログ・ブラウザーUI・platform viewの収録、高速アニメーションの全フレーム取得、WindowServerのないホスト、Linux/Windowsは検証対象外。

## 再現と終了

[日本語ヘッドレスガイド](../../../../docs/ja/headless.ja.md)に起動・接続・録画・終了の手順をまとめた。毎回新しいprivate directoryとruntime/session/出力先を用意し、VM Service URIを再取得する。Androidの自動検証では`MARIONETTE_RECORD_FPS=2`を指定する。

全CLI sessionをcloseし、record smokeのdaemonが残っていないことを確認。所有するmacOSアプリ・Chrome・Android Emulator・Flutter runner・iOSアプリは終了済み。専用iOSデバイスはshutdown/deleteし、一時AVDとURIファイルを削除した。共有の端末とadb serverは維持した。生ログと認証URIをPRへ掲載しない。
