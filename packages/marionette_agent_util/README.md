# marionette_agent_util

OS・端末ごとのコマンド、ネイティブAPI、依存ツールの判定と、操作対象Flutterアプリのdebug用補助機能をここへ集約する。

用途に応じて公開ライブラリを選ぶ。

- `package:marionette_agent_util/marionette_agent_util.dart`: ホスト側の録画・アプリ起動・端末管理。Flutterをimportせず、Dart VM／コンパイル済みCLIで実行できる。
- `package:marionette_agent_util/flutter.dart`: Flutterアプリ側の型付き観測・操作と非表示時の描画維持。ホスト側のOS処理をexportしない。

CLI・util・exampleはPub workspaceを共有する。依存取得にはFlutter SDKが必要で、リポジトリルートで`flutter pub get`を一度実行する。lockfileとpackage configはルートだけで管理する。

CLI解析・JSON envelope・session/ref・VM Service操作には依存しない。CLIは公開APIを呼び出して`PlatformException`を製品エラーへ変換する。隣接リポジトリやMCPプロセスには依存しない。

共通の`PlatformException`と終了通知の`terminationRequests()`も提供する。アプリの終了手順は呼出元が所有し、OS別のsignal選択・購読解除はutilへ閉じ込める。

## Flutterアプリのdebug用補助機能

旧`marionette_agent_flutter`の機能はこのパッケージへ統合した。アプリの依存先を`marionette_agent_util`へ変更し、importを`package:marionette_agent_util/flutter.dart`へ置き換える。公開関数とextension名は維持する。

`MarionetteBinding.ensureInitialized(...)`の後、`runApp(...)`の前に`registerAgentExtensions()`を呼ぶ。debug時だけ、CLI向けの型付き観測・操作providerを登録する。public Widget/State APIと固定`marionette_flutter: 0.6.0`を使い、入力値、有効・無効、チェック状態、labelなどを観測する。対応操作と制約は[追加コマンド仕様](../../docs/ja/cli-parity.ja.md)を参照。

診断文字列からの推測、パスワード値の公開、未構築の遅延リスト項目の生成、完全なSemanticsツリーの提供は行わない。releaseではextensionを登録しない。

### 非表示時の描画維持

非表示のdebugアプリを明示的に起動するときだけ、binding初期化後、`runApp`前に`enableHeadlessRendering()`を呼ぶ。OSがhidden／paused／detachedを通知している間、16msごとに強制フレームを要求する。native lifecycleや通知は書き換えず、表示状態への復帰または返却されたdispose関数の呼出しで要求を止める。releaseでは何もしない。

ウィンドウの非表示化やnative engineの起動は行わない。[ヘッドレスガイド](../../docs/ja/headless.ja.md)のnative window設定と組み合わせる。native pluginは実際のOS環境で動作する。非表示中も描画のリソースを使うため、明示的なdebug自動化に限定する。

## 開発・検証

ホスト側のテストは`test/`、Flutter engineを使うテストは`flutter_test/`に配置する。

依存取得後、次の検証をこのパッケージ内で実行する。

```sh
dart format lib test flutter_test
dart analyze
dart test
flutter test flutter_test
```

## Screen recording

- `RecordingManager`: owner/sessionごとの開始・状態・停止・close・dispose、端末排他、排他的な出力予約。
- `ScreenRecorder` / `RecordingHandle`: backend境界。startはbackend固有の開始確認後に完了、stopは動画確定後に完了する。`isRunning`と`ended`でprocess終了を確認でき、終了未確認の端末予約は解放しない。iOSは最初のフレーム、Androidは動画headerの生成を確認する。macOS標準コマンドにはfirst-frame通知がないため、起動後1秒間の生存を確認し、動画の生成はstopで検証する。
- `PlatformScreenRecorder`: iOS Simulator=`xcrun simctl`、Android=`adb shell screenrecord`、macOS=`/usr/sbin/screencapture`。
- Linux/Windowsの録画は`UNSUPPORTED_CAPABILITY`。未知のCLI platform名は`INVALID_ARGUMENT`。

macOSホストでの利用を対象とする。iOSは起動済みSimulatorのUDID、Androidはオンラインかつ認証済みのadb serial、macOSは1から始まるdisplay indexを明示する。iOS実機録画は未対応。出力はiOS/Androidが`.mp4`、macOS/Webが`.mov`。音声は収録しない。録画範囲は端末／ディスプレイ全体であり、OSが保護するコンテンツの録画を保証しない。

macOSでは実行元アプリへの画面収録許可が必要。既定は非対話実行で、許可の自動変更はしない。Androidは180秒で自動停止し、自動停止後も動画を回収してstatusを更新する。回転中の動画や長時間分割結合は保証しない。

動画は出力先と同じ親directory内のprivate staging directoryに書き、確定後に予約済み出力先へコピーする。失敗時のstagingは`recoveryPath`として保持する。既存file/directory/symlinkは上書きしないが、予約後に別プロセスが意図的に保存先を差し替える競合は保証外。

`stop`の要求期限超過でも、backendの有界な終了・回収処理は継続し、完了まで端末を予約する。`status`で最終状態を確認する。OSの端末／ディスプレイ録画はVM Serviceの切断で止まらない。daemonの正常終了は録画を確定する。SIGKILLやホスト停止後の自動復元は未対応。

### Web

`WebScreenRecorder`はmacOSの可視Chromeと明示したディスプレイの組を扱う。deviceは`display:1@ws://127.0.0.1:9222/devtools/page/<ID>`。Chromeの専用debug profile、loopback接続、実行元へのmacOS画面収録許可が必要。Chrome以外/headless/他ホストは未対応。画面全体を既存macOS backendでMOVへ保存し、ブラウザーUI・同じdisplayのOSダイアログ・他アプリを含む。配置は利用者が行い、CLIはウインドウを移動・追従しない。

CDPは対象識別と終了監視だけに使用し、録画はFlutter/VM Serviceに依存しない。タブ終了・クラッシュ・接続断はCONNECTION_LOSTとしてnative停止へ合流し、部分動画を復旧用に残す。nativeの権限エラーと依存欠落は共通PlatformExceptionへ伝播する。RecordingTarget.keyはWebもmacosのdisplay keyを使い、同一daemonの物理display排他を共有する。仕様と方式比較は[Web録画方式](../../docs/web-recording.md)、使用手順は[CLIリファレンス](../../docs/ja/cli-reference.ja.md)を参照。

Web開始時はCoreGraphicsの`CGPreflightScreenCaptureAccess`をDart FFIで読み取り、未許可ならChrome接続・native録画の前にIO_ERRORで拒否する。許可要求APIは呼ばない。APIを利用できない環境はUNSUPPORTED_CAPABILITYとする。

### FlutterアプリのPNG録画

`PngScreenRecorder`へcapture/closeを注入すると、表示ウィンドウや画面収録許可に依存せず、アプリが返すPNGを無音H.264 MP4へ保存できる。接続自体は呼出元のadapterが所有し、録画実装はFlutter・VM Serviceをimportしない。`RecordingManager.start(recorder: ...)`で個別recorderを選ぶ。`RecordingPlatform.flutter`のdeviceはsession識別子で、OS端末録画とは独立して排他にする。

既定10fpsは取得間の待機間隔であり、取得頻度を保証しない。実取得時刻のVFRとしてffmpegで確定する。PNGはprivate stagingへ逐次保存するため録画時間に応じて容量が必要。先頭PNGで開始確認し、PNG取得失敗・寸法変更・encoder失敗を失敗として保持する。OS画面や音声は含まない。開始・保存保護・有界停止・abortは共通契約に従う。詳細は[SPEC](../../docs/ja/SPEC.ja.md#flutterアプリのヘッドレス録画issue-20)を参照。

## アプリ実行環境

`LaunchOptions`と`PlatformApplicationLauncher.start(options, deadline)`でtester／ios／android／macos／webを明示選択する。返却`RunningApplication`はuri、秘匿可能なdescription、exited、stopを持つ。接続やMarionette操作は呼出元へ委ね、utilがprivate一時領域・SDK/OSコマンド・起動準備・project排他・子プロセスと端末の終了を所有する。`dispose`は起動途中を含めて回収する。詳細は[ヘッドレスガイド](../../docs/ja/headless.ja.md)と[SPEC](../../docs/ja/SPEC.ja.md#ハイブリッド実行環境issue-20追加仕様)を参照。
