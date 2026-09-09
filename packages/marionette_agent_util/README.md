# marionette_agent_util

`marionette_agent`専用の内部プラットフォームサービス。録画専用のパッケージではなく、OS・端末ごとのコマンド、ネイティブAPI、依存ツールの判定をここへ集約する。将来の端末情報取得などは独立したサービスとして追加する。

CLI解析・JSON envelope・session/ref・VM Service操作には依存しない。CLIは公開APIを呼び出して`PlatformException`を製品エラーへ変換する。隣接リポジトリやMCPプロセスには依存しない。

共通の`PlatformException`と終了通知の`terminationRequests()`も提供する。アプリの終了手順は呼出元が所有し、OS別のsignal選択・購読解除はutilへ閉じ込める。

## Screen recording

- `RecordingManager`: owner/sessionごとの開始・状態・停止・close・dispose、端末排他、排他的な出力予約。
- `ScreenRecorder` / `RecordingHandle`: backend境界。startはbackend固有の開始確認後に完了、stopは動画確定後に完了する。iOSは最初のフレーム、Androidは動画headerの生成を確認する。macOS標準コマンドにはfirst-frame通知がないため、起動後1秒間の生存を確認し、動画の生成はstopで検証する。
- `PlatformScreenRecorder`: iOS Simulator=`xcrun simctl`、Android=`adb shell screenrecord`、macOS=`/usr/sbin/screencapture`。
- Web/Linux/Windowsの録画は`UNSUPPORTED_CAPABILITY`。未知のCLI platform名は`INVALID_ARGUMENT`。

macOSホストでの利用を対象とする。iOSは起動済みSimulatorのUDID、Androidはオンラインかつ認証済みのadb serial、macOSは1から始まるdisplay indexを明示する。iOS実機録画は未対応。出力はiOS/Androidが`.mp4`、macOSが`.mov`。音声は収録しない。録画範囲は端末／ディスプレイ全体であり、OSが保護するコンテンツの録画を保証しない。

macOSでは実行元アプリへの画面収録許可が必要。既定は非対話実行で、許可の自動変更はしない。Androidは180秒で自動停止し、自動停止後も動画を回収してstatusを更新する。回転中の動画や長時間分割結合は保証しない。

動画は出力先と同じ親directory内のprivate staging directoryに書き、確定後に予約済み出力先へコピーする。失敗時のstagingは`recoveryPath`として保持する。既存file/directory/symlinkは上書きしないが、予約後に別プロセスが意図的に保存先を差し替える競合は保証外。

`stop`の要求期限超過でも、backendの有界な終了・回収処理は継続し、完了まで端末を予約する。`status`で最終状態を確認する。VM Serviceの切断は録画を止めない。daemonの正常終了は録画を確定する。SIGKILLやホスト停止後の自動復元は未対応。

```sh
dart pub get
dart format lib test
dart analyze
dart test
```
