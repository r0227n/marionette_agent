# CLIクリティカルレビューの検証記録

2026-09-13、`feature/cli-critical-review` で実施。[レビュー結果](../../../../docs/cli-critical-review.md) の修正を対象とする。人間による確認は未実施。

この文書は初回43呼び出しの記録。develop統合後はscriptを47呼び出しへ拡張し、[再検証記録](critical-review-develop.md) に追加確認を記載した。

## 自動検証

- 整形と静的解析に問題なし。全291テスト成功。
- 修正前は既存281テストが成功する一方、findの対象置換4ケース、dragの同一観測、batchの環境設定継承の新規6ケースが失敗した。修正後はすべて成功した。
- findは選択後に同じkeyの異なる属性へ置換した場合、tap/fill/focus/scrollintoviewを送信せず `STALE_REF` を返す。
- dragは両対象を1回のinspectで検証する。終点が変わった場合は送信せず、始点のrefも失効させない。
- 12,000行を逆順にしたsnapshot差分を5秒の要求期限内に比較。重複件数、ネストしたmapのkey順序、整数・小数の等価性も確認。
- daemon側モジュールからCLI構文、args、公開barrelへの逆依存を検出する構造テストを追加。

## 実環境

macOS、Flutter 3.47.2 / Dart 3.13.2、iPhone 17 Pro / iOS Simulator 26.2、UDID `022CF629-91E1-48F0-816B-2D86B8CD1D38`。`example/` を新規起動し、専用runtimeとsession `critical` で [critical_review_smoke.dart](../../integration_test/critical_review_smoke.dart) を実行した。43回のCLI呼び出しが期待した終了コード・JSON結果に一致した。古いrefの再利用だけは期待どおり終了コード4、それ以外は0。

| 操作 | 実測結果 |
| --- | --- |
| help / version / doctor quick / workflow schema | 出力成功、doctorの失敗なし |
| connect → snapshot → refでtap → 同じrefでtap | `Tap count: 1`。再利用は `STALE_REF` / `not_sent` |
| find key → fill → get value | 入力値 `reviewed`、画面に8 characters |
| swipe page_view left、distance 250 → wait 500 | `Current page: 2`、動画でもPage 2を確認 |
| find label → focus、find placeholder → type | AdvancedのEditable valueが `reviewed` |
| scrollintoview → snapshot → 2つのrefでdrag | `Drop: item`。動画でdrag途中とdrop後を確認 |
| snapshot保存 → diff snapshot | `changed: false` |
| 不正な環境session/timeoutを明示CLIで上書きしてbatch | 4ステップ完了、`checked: true` |
| 同じbaselineとdiff snapshot | `changed: true`、チェック状態と表示テキストの変化を検出 |
| record stop → state save → close → state load → snapshot | 録画確定、接続復元成功、復元後snapshot成功 |
| 最後のcloseと環境終了 | daemonのsocket/metadata消失、runner正常終了・PID消失、アプリのlaunch service消失、Simulator Shutdown |

動画はH.264、1206×2622、394 frames、27.195秒。デコード成功を確認し、抽出フレームを目視した。CLIの録画経過時間は起動・終了処理を含む30,943ms。3枚の画像も目視済み。

## CLI実測の抜粋

以下はリポジトリルートからの表記へ変換した実行引数。runtimeは外部の専用ディレクトリを `MARIONETTE_AGENT_RUNTIME_DIR` に設定した。`<evidence>` は今回の出力先を置換したもので、再現時は書き込み可能な出力先へ置き換える。入力は記載した引数とファイルのみ、stdinは不使用。以下のstderrはすべて空。stdoutは抜粋と明記した箇所以外は全量。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --session critical --timeout 30000 tap @e3
```

同じrefへの2回目の実行。終了コード4。

```json
{"schemaVersion":1,"ok":false,"session":"critical","data":null,"error":{"code":"STALE_REF","message":"Ref is not valid in this session","hint":"Run snapshot again","outcome":"not_sent"}}
```

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --session critical --timeout 30000 find key text_input fill reviewed
dart packages/marionette_agent/bin/marionette_agent.dart --json --session critical --timeout 30000 get value --key text_input
```

両方とも終了コード0。stdoutは順に以下。

```json
{"schemaVersion":1,"ok":true,"session":"critical","data":{"requiresSnapshot":true},"error":null}
{"schemaVersion":1,"ok":true,"session":"critical","data":{"property":"value","known":true,"value":"reviewed"},"error":null}
```

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --session critical --timeout 30000 drag @e15 @e16
dart packages/marionette_agent/bin/marionette_agent.dart --json --session critical --timeout 30000 get text --key drop_result
```

両方とも終了コード0。stdoutは順に以下。refは直前のsnapshotで取得した始点・終点の値で、再現時は取り直す。

```json
{"schemaVersion":1,"ok":true,"session":"critical","data":{"requiresSnapshot":true},"error":null}
{"schemaVersion":1,"ok":true,"session":"critical","data":{"text":"Drop: item"},"error":null}
```

batch実行時だけ環境変数 `MARIONETTE_AGENT_SESSION` を空文字、`MARIONETTE_AGENT_TIMEOUT_MS` を `invalid` に設定。明示CLIのsession/timeoutが優先されることを確認した。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --session critical --timeout 30000 batch '<evidence>/batch.json'
```

入力ファイルの全量:

```json
[["find","key","advanced_checkbox","check"],["wait","200"],["is","checked","--key","advanced_checkbox"],["logs"]]
```

終了コード0、stdout全量:

```json
{"schemaVersion":1,"ok":true,"session":"critical","data":{"completed":4,"results":[{"command":"find","data":{"requiresSnapshot":true}},{"command":"wait","data":{"waitedMs":200,"requiresSnapshot":false}},{"command":"is","data":{"property":"checked","known":true,"value":true}},{"command":"logs","data":{"entries":["example started","tap button pressed: 1","text input changed","page changed: 2"],"configured":true}}]},"error":null}
```

## 人間による再現

1. `example/` の依存を解決し、専用Simulatorでdebug起動する。アプリを完全に再起動してTap count 0、Page 1、未入力、Checked false、Drop noneへ戻す。他タスクのSimulatorは使用しない。
2. 新しく表示されたVM Service URIを手元で取得し、専用runtimeを設定してsession `critical` を接続する。URIとstateファイルは非公開として扱う。
3. snapshotで `tap_button` のrefを取得し、tapする。Tap count 1になること、同じrefへの再tapが拒否されることを確認する。
4. 上記find fillを実行し、入力値と8 charactersを確認。page_viewを左へ250 swipeし、500ms待ってPage 2を確認する。
5. advanced_tabへ移動。label `Editable value` のexact focus、placeholder `Type here` のexact typeで `reviewed` を入力する。advanced_focusへfocusを移してキーボードを閉じる。
6. advanced_dragをscrollintoviewし、300ms待ってsnapshotを取得。advanced_dragとadvanced_dropの新しいrefでdragし、Drop: itemを確認する。
7. advanced_checkboxをscrollintoviewし、300ms待ったsnapshotをbaselineファイルへ保存する。diff snapshotで変更なしを確認後、上記batchを実行する。Checked trueとdiffの変更ありを確認する。batch内の200ms待機はアプリの描画反映を待つため。
8. state save、close、state loadの順に実行し、snapshotを再取得できることを確認する。最後にclose、アプリとrunnerを終了し、専用SimulatorをShutdownする。private URI/stateファイルを削除する。

再実行用scriptはCLIパッケージを作業ディレクトリとし、`MARIONETTE_TEST_PRIVATE` に短い専用ディレクトリ、`MARIONETTE_TEST_VM_URI_FILE` にURIファイル、`MARIONETTE_TEST_DEVICE` にUDIDを渡す。scriptは43呼び出しの結果を保存し、成功時にstateファイルを削除してsessionを閉じる。Simulator・runnerの起動と終了は呼出側が担当する。

- [ ] 人間が上記の画面と状態を確認した

## エビデンスと限界

Draft PRへ `controls.png`（tap/fill後）、`input.png`（Advanced入力欄）、`advanced.png`（checked/drop後）、`gestures.mp4`（swipeからAdvanced操作まで）を添付する。完全なCLI結果は検証出力の `results.json` に保存した。認証URIを含む接続ファイルは削除済み。

このシナリオはiOS Simulatorで実施した。Android/Webの実環境確認は今回実施していない。findの要素置換競合とdragの観測一貫性は決定的なfakeで検証した。アプリ側の原子的な選択・送信や永続identityは提供しないため、同一属性の別要素への置換まで検出する保証はない。
