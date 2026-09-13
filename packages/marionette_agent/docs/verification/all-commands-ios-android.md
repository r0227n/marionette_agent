# 全コマンド: iOS / Android動作確認

実施日: 2026-09-13。ブランチ: `feature/all-commands-workflow`。製品コードは `743597f2245452c2da7f5ee366df76533e9eee86`。変更対象は検証YAML、検証スクリプト、そのテスト・文書で、CLIやbindingの製品実装は変更していない。

再現手順と全コマンドの合格条件は [workflows/README.md](../../examples/workflows/README.md) に記載した。[all-actions.yaml](../../examples/workflows/all-actions.yaml) はworkflow v1の6 actionを使う16ステップ。[all_commands_smoke.dart](../../integration_test/all_commands_smoke.dart) はCLIの全23コマンド・サブコマンドとhelp/version、close --allを実行する。

## 環境

| 項目 | 検証環境 |
| --- | --- |
| ホスト | macOS 26.5.2 / Xcode 26.3 |
| Flutter / Dart | 3.47.2 / 3.13.2 |
| marionette_mcp / marionette_flutter | 0.6.0 / 0.6.0（pub固定依存） |
| iOS | iPhone 17 Pro / iOS 26.2、UDID `022CF629-91E1-48F0-816B-2D86B8CD1D38` |
| Android | Pixel 9 Proプロファイル、Android 16 / API 36 / arm64-v8a、Emulator 36.3.10.0 |
| Android AVD / serial | 今回作成した `mra_all_a08ghyp2` / `emulator-5580` |
| アプリ | このcheckoutの `example/` をdebug起動、bundle ID `com.example.example` |
| 資源分離 | OSごとに専用runtime・session・成果物。共有利用記録 `/tmp/mra-simulator-leases.json` に予約 |

## 結果

両OSで全84回のCLI呼出しが期待どおりに完了した（各78回が終了0、6回が期待するエラー）。全23コマンド・サブコマンドとhelp/versionの実行を記録から照合した。以下はすべて両OSで成功した。

| 確認対象 | 実際の結果 |
| --- | --- |
| doctor / connect / session | 独立VM probe成功、同じURIへの再接続成功、接続前0件・接続後1件 |
| snapshot / get / is visible | 初期カウンタ0、Text件数一致、非存在count=0、論理bounds、ボタンのknown=true/value=true |
| tap / fill | ref・座標tapでカウンタ0→1→2、入力16→3→0→16文字 |
| swipe / scroll / wait | Page 1→2→1、Bottom reached、About exists / Controls gone |
| logs / screenshot | 手動ログ追加を確認、PNG/JPEG/注釈PNGを復号・目視確認 |
| workflow schema / validate / run | 全体と6 actionのschema取得、16ステップ検証・実行完了、finalSnapshotのログボタンrefを別CLIで使用、最後のカウンタ3 |
| record start / status / stop | 操作・workflow中に録画継続、MP4確定、stopの再実行で同じpath/bytes |
| close / close --all | 再connect後も終了成功、全close後0件、socket/metadata消失 |
| エラー系 | NOT_CONNECTED×2、STALE_REF、TARGET_NOT_FOUND、AMBIGUOUS_TARGET、UNSUPPORTED_CAPABILITY。拒否tapでカウンタは不変 |

`dart format integration_test/all_commands_smoke.dart test/workflow_model_test.dart` は変更0件、`dart analyze` はNo issues found、`dart test` は262件全成功（最終版・79秒）。`example/` の `flutter test` も6件全成功。通常テストに追加したYAML検証は、全actionの網羅と最終snapshotを確認する。文書の相対リンクと `git diff --check` も確認した。

### エビデンス

| OS | 保存先 | 録画 |
| --- | --- | --- |
| iOS | `/tmp/mra-all-a08ghyp2/evidence/ios-fbftVb/` | H.264、1206×2622、49.285秒、383 frames、2,464,948 bytes |
| Android | `/tmp/mra-all-a08ghyp2/evidence/android-q8r7IP/` | H.264、720×1280、56.578秒、420 frames、1,762,422 bytes |

各保存先の `results.json` に84呼出しの結果、`media-checks.json` に画像・動画のSHA-256と復号結果、`visual-review.json` に目視確認とコマンド網羅の記録を保存した。スクリプトが出力する `results.json.visualReview` は自動確認時点のpendingを維持し、その後の目視結果を別ファイルに記録している。認証URI・raw Flutterログは添付しない。

各OSの `initial.png`、`initial-jpeg.jpg`、`initial-annotated.png`、`filled-page-two.png`、`scrolled.png`、`workflow-bottom.png`、`about.png` の全7枚を開いた。初期カウンタ0、注釈位置、16文字・カウンタ2・Page 2、Bottom reached、AboutのWorkflow fixtureを確認した。動画は全フレームを復号し、8時点のフレームを開いて入力・ページ往復・スクロール・タブ遷移との対応を確認した。

最終結果に対応する画像14枚と `operations.mp4` 2本をPR添付対象とする。`images-reviewed.png` / `video-reviewed.png` はローカル目視用の一覧画像。

### 後始末

両OSのrecord stop、close --all、専用runtimeのsocket/daemon metadata消失を確認した。runnerへ `q` を送り終了0、アプリのプロセス不在を確認し、iOSをShutdown、Android Emulatorを停止した。利用記録をreleasedへ更新し、私有URIを削除した。今回作成した空AVDも停止後に削除した。証跡と私有runnerログは保存している。

## 検証手順を調整した理由

- 初回YAML検証でwaitの必須 `state` が不足していた。明示して修正し、schema/binding検証と、全actionが含まれることを通常テストに追加した。
- 座標swipeの移動距離200pxでは、両OSとも成功応答でもPage 2のままだった。iOSの338px幅、Androidの362.67px幅の実boundsを確認し、幅の80%（270.4px / 290.13px）を動かすと2→1が成立した。成功応答はページ確定を保証しないため、検証側のジェスチャー距離を修正した。
- iOSのListViewは400pxのscroll一回で400px動いたが、Bottom reachedはまだ画面外だった。上向き400pxと150pxの2ジェスチャーを手順に明示し、後続wait/get/snapshotで到達を確認するようにした。失敗時の自動再送は追加していない。
- 2回目も400pxにした試行ではiOSのoverscroll中に最終snapshotを取得し、log_buttonのyが525.26から静止後644へ変化した。後続のref操作がSTALE_REFで拒否されるのは仕様どおりだった。2回目を150pxにして跳ね返りを避けると、最終refを別CLIから使う確認も成功した。比較記録は `/tmp/mra-all-a08ghyp2/evidence/ios-ref-comparison.json`。
- 最初に使用した既存Pixel_9_Pro AVDは再install時に `INSTALL_FAILED_INSUFFICIENT_STORAGE` となった。既存AVDのユーザーデータを削除せず、既存system imageから検証専用の空AVDを作成した。新AVDでは起動直後の `/data` 空き4.8GBを確認した。

この調整は製品の不具合修正ではなく、到達保証を持たないgestureに対する検証条件と実行環境の修正である。途中失敗の記録は `/tmp/mra-all-a08ghyp2/evidence/ios-7kRbyZ/`、`ios-hO7Is3/`、`android-yAnzah/`、`ios-DrJpMD/`、`ios-IT6xXU/` に保持した。

## 範囲と制約

全コマンドの代表的な正常系と、未接続・stale・不存在・曖昧さ・未対応selectorのエラー系を確認する。全オプションの組合せや全OS版・端末の互換性保証ではない。`doctor` はmacOSホスト/iOS Simulator診断であり、Android SDK診断を追加したわけではない。`screenshot --annotate` はexampleのopt-in providerを使用する。binding 0.6.0のidentifier操作は `UNSUPPORTED_CAPABILITY` が期待結果である。

人間による再現確認は未実施。再現する際は同じbranchで未使用端末を割り当て、アプリを新規起動し、URIを取り直して上記READMEのスクリプトを実行する。

- [ ] 人間がiOS/Androidで手順を再現し、画面と動画を確認した
