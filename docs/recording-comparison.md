# iOS録画方式の比較（2026-09-10）

## 結論

端末画面の証跡を残すrecordには、現在の`xcrun simctl io <UDID> recordVideo --codec=h264`を維持する。日本語ソフトウェアキーボードと変換候補を含むことを実動画で確認した。marionette_mcpの録画は入力結果とFlutterのレイアウト変化を収録するが、キーボードの領域が空白となる。

上流の録画を再実装する変更や、自動fallbackは追加しない。Flutter描画だけを収録する機能が必要になった場合は、収録範囲を明示した別方式として検討する。その場合、VM Serviceを使う処理はbackend adapterに置き、OS処理用のutilへmarionette_mcp依存を持ち込まない。

## 対象と手順

- PR実装: `3dfaace`、iPhone 17 Pro Simulator / iOS 26.2。
- example: Flutter 3.47.2、pubのmarionette_flutter 0.6.0。
- 比較対象: leancodepl/marionette_mcpの`08800422de1e6416986c6883fc060ab1e08c425e`に含まれるmarionette_cliの`record-video`とmarionette_mcpの録画pipeline。録画ロジックは変更せず、一時package_configから参照した。
- アプリ側の`screencast_service.dart`は上記commitとpub 0.6.0で同一であることをcmpで確認。
- 前回のiOS検証ではソフトウェアキーボードが非表示だった。今回はSimulatorのI/O → Keyboard → Toggle Software Keyboardで表示を確認した。

同じSimulatorで次の2コマンドを同時に開始し、入力欄tap → 仮想キー「あ」「か」 → 変換確定 → キーボード終了を操作した。開始時点と終了時点は厳密には一致しない。simctl側は約29秒でSIGINT停止、上流側は35秒指定で終了。simctlの停止はキーボードを閉じる直前であり、終了後のレイアウト復元は上流動画で確認した。認証URIは証跡に記録しない。

```sh
xcrun simctl io 022CF629-91E1-48F0-816B-2D86B8CD1D38 recordVideo --codec=h264 simctl-keyboard.mp4
marionette --uri '<VM Service URI>' record-video --output mcp-keyboard.webm --duration 35 --transport tcp --verbose
```

| 観測内容 | simctl | marionette_mcp pipeline |
| --- | --- | --- |
| 日本語キーボード・変換候補 | 映る | 映らず、その領域が空白 |
| 入力結果「あか」 | 映る | 映る |
| キーボード出現によるFlutter領域縮小 | 映る | 映る |
| OSの時刻・電波・バッテリー表示 | 映る | 映らない |

同じ動画時刻の厳密同期比較ではなく、入力結果「あか」かつ変換中という同じUI状態のフレームを比較した。端末動画とFlutter screenshotの比較で代用せず、両方式とも実際に動画を生成した。

## 実装の差

上流は`RenderView.layer`をSceneBuilderへ追加し、`Scene.toImage` → raw RGBA → TCP/WS → ホスト側ffmpegでVP8/WebMにする。NativeScreencastServerのnativeは転送経路の区別であり、OS画面の取得を意味しない。[上流ソース](https://github.com/leancodepl/marionette_mcp/blob/08800422de1e6416986c6883fc060ab1e08c425e/packages/marionette_flutter/lib/src/services/screencast_service.dart)と[Scene.toImage公式仕様](https://api.flutter.dev/flutter/dart-ui/Scene/toImage.html)を参照。

今回のutilはsimctlの最初のフレーム通知を待ち、停止時はSIGINT後にプロセス終了を待つ。この順序はインストール済みsimctlのhelpと一致する。上流方式はbinding・接続・フレーム転送・ffmpegが必要になる一方、OS別録画コマンドを持たずFlutter側の共通処理を使える。現在の方式はXcodeなどOSごとの依存と保守が必要だが、VM Service接続前から録画できる。CPU、メモリー、転送量、操作遅延は測定していない。codec・録画時間・収録範囲が異なるので、ファイルサイズを性能比較には使わない。

## 動画検証

全動画は1206×2622。原本は次のディレクトリに保存した。

| ファイル | codec | duration / bytes |
| --- | --- | --- |
| `/tmp/mra-keyboard-compare-v2/simctl-keyboard.mp4` | H.264 | 28.786667秒 / 6,299,987 |
| `/tmp/mra-keyboard-compare-v2/mcp-keyboard.webm` | VP8 | 35.920000秒 / 2,723,135 |
| `/tmp/mra-keyboard-product/operations.mp4` | H.264 | 14.633333秒 / 2,064,026 |
| `/tmp/mra-keyboard-product/close.mp4` | H.264 | 2.028333秒 / 449,729 |

上流動画と製品CLIの2動画は`ffmpeg -v error -i <video> -map 0:v:0 -enc_time_base:v demux -fps_mode passthrough -f null -`で全フレーム復号し、終了0・stderrなし。同時録画のsimctl原本は終了0だがnull出力のmuxerでnon-monotonic DTS警告が3件出た。ffprobeで取得した1415フレームのPTSには逆行なし。診断用に`-vf 'setpts=N/(30*TB)'`で時刻を付け直して全フレームを復号すると終了0・stderrなし。原本は変更していない。警告の根因と他playerでの影響は未確定であり、完全な時刻整合性の確認済みとはしない。

追加で製品CLIの`integration_test/record_smoke.dart`を、MARIONETTE_RECORD_PLATFORM=ios、MARIONETTE_RECORD_DEVICE=上記UDID、MARIONETTE_TEST_VM_URI_FILE=/tmp/mra-compare-ios-uri、MARIONETTE_RECORD_EVIDENCE=/tmp/mra-keyboard-productとして実行。接続なし録画開始、tap/fill、状態照会、stop、重複stop、上書き拒否、closeによる確定がすべて成功。12秒のフレームで`record verification`、19 characters、日本語仮想キーボードを確認した。

OSダイアログ、PlatformView、保護コンテンツ、アプリクラッシュ後の継続は今回実測していない。macOS実録画は後続検証で成功した。Androidの上流方式との同時比較も今回の対象外。iOSの観測結果をこれらへ一般化しない。
