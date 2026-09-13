# develop統合と再レビューの検証

2026-09-13、PR #40の `feature/cli-critical-review` へ `origin/develop` の `3ddda4897b11a778fd91d7572a85c2c00ffb87b1` をmergeした。mergeコミットは `96beb4a`。変更内容は [レビュー記録](../../../../docs/cli-critical-review.md) を参照。人間の確認は未実施。

## 自動検証

競合解消後、skills・AOT install/upgrade・共通オプション・find/drag・batch・diff・依存方向の関連28テストが成功。続く再レビューで設定エラーの出力契約とfrontmatterの検証漏れを再現した。新規2テストは修正前に失敗し、修正後に成功した。

最終コードの整形・静的解析は問題なし。全303テストが成功（並列数2）。AOT配布の移動可能なbundle、失敗したupgradeでの旧版保持、IPC、workflow、session、対象解決、画像、録画を含む。

## CLIの追加確認

同じexample・Simulator・起動手順は [初回検証](critical-review.md) を参照。`critical_review_smoke.dart` は47呼び出しへ拡張した。skills help/pathを接続前に実行してruntimeが生成されないこと、接続後snapshotとtapの間にskills pathとconfig失敗を挟んでもrefを使えることを追加確認する。初回の43呼び出しの記録は過去の実測として保持する。

以下は今回の製品CLIの実測抜粋。実行ファイルをリポジトリルート基準へ変換し、外部pathは `<verification-directory>` へ置換した。stdin入力はなく、stderrはすべて空。認証URIを掲載していない。

接続とsnapshotの後、直前のrefを保持したまま実行:

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --session critical --timeout 30000 skills list --config '<verification-directory>/absent-config.json'
```

入力ファイルは存在しない。終了コード1、stdout全量:

```json
{"success":false,"error":"Config must be a regular JSON file of at most 1 MiB"}
```

その後、同じsnapshotのtap_buttonのrefでtapして `Tap count: 1` を確認。古いrefへの再tapは終了4 / STALE_REF / not_sentとなった。入力・Page 2へのswipe・drag/drop・batch・diff・state保存と復元も期待した結果になった。

frontmatterは別の私有ディレクトリに5つのfixtureを作り、`MARIONETTE_AGENT_SKILLS_DIR` に設定して製品CLIでも確認した。name validのLFとname crlfのCRLFは正常。空name、開始行 `---invalid`、終了行 `---invalid` の3種類は不正とした。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart skills list --json
```

終了コード0、stdout全量:

```json
{"success":true,"data":[{"name":"crlf","description":""},{"name":"valid","description":"Valid guide"}]}
```

このローカル確認でもruntimeは未生成。get --allからの除外、設定ファイルの不正JSON・未知option、textモードのstderrのみの出力は回帰テストで確認済み。

## 画面確認と終了処理

アプリを初期化して2回実行し、各47呼び出しが期待した終了値・JSONと一致した。最終実行のCLI screenshotを開き、以下の3枚を確認した。今回追加したskills呼出しが既存refや操作に干渉しないことを、CLI応答と画面の両方で確認した。

| 画像 | 確認した状態 |
| --- | --- |
| controls.png | configエラー後のref tapでTap count 1、find fillでreviewed / 8 characters |
| input.png | label/placeholderから操作したAdvanced入力欄にreviewed |
| advanced.png | batch後のChecked true、drag後のDrop: item |

新規録画はPRへ添付しない。record stopは成功しファイルを読めたが、全フレームのデコード時刻が逆行した。最初の実行は8.466667秒から3.73秒、Simulator再起動後の再実行も11.35秒から5.89秒へ戻った。CLIの今回の変更が原因かは特定していない。画像と状態で操作結果は確認できたが、今回の録画の時間軸は未検証として残す。初回PRの動画は初回commitの証跡であり、統合後の録画品質を保証しない。

両実行ともrecord stopとsession closeが成功し、daemonのmetadata/socketが消えたことを確認。runnerは終了コード0、そのPIDとアプリのlaunch serviceは存在しない。所有SimulatorのShutdown、private URI/stateの削除まで確認し、利用記録を解放した。

## 人間の確認

1. [初回検証の再現手順](critical-review.md#人間による再現) に従い、アプリを初期化して新しいprivate URIと専用runtimeを用意する。
2. 接続前にskills help/pathが使え、runtimeを作らないことを確認する。
3. 接続・snapshot後にskills pathと上記configエラーを実行し、JSONは専用形式・終了1、textはstderrのみとなることを確認する。直前に取得したrefでtapし、カウンタが1になることを確認する。
4. 上記5種類のSkill fixtureを専用ディレクトリへ作ってoverrideし、list/get --allが正常な2種類だけを返すことを確認する。終了時にoverrideを解除する。
5. 初回手順のfind/swipe/drag/batch/diff/state復元も確認し、所有session・runner・アプリ・Simulatorを終了してprivate URI/stateを削除する。

- [ ] 人間が統合後の変更と画面を確認した

実環境確認はmacOS / Flutter 3.47.2 / Dart 3.13.2、iPhone 17 Pro / iOS 26.2（UDID `022CF629-91E1-48F0-816B-2D86B8CD1D38`）。Android/Webの実環境確認は今回実施していない。
