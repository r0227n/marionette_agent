# SSOT / SOLIDレビューの検証

2026-09-20。基点 `ec7834e`、作業ブランチ `feature/ssot-solid-review`。[レビューと修正内容](../../../../docs/ssot-solid-review.md) を参照。

## 環境と自動検証

macOS / Flutter 3.47.2 / Dart 3.13.2。専用のiPhone 17 Pro / iOS 26.2 Simulatorを使用した。CLI runtime・session・出力を他タスクから分離した。

変更前のCLI全314テストが成功。新規回帰テストではcloseの切断失敗・期限超過、find入力、waitの明示null、close --allのエラーscopeを再現した。所有アプリ終了との競合テストも修正前に失敗した。修正後はformat・analyzeに問題なく、全322テストが成功した。schema、workflow、action policy、ref、recording、launch、IPC、AOT実行を含む。

実環境は [ssot_smoke.dart](../../integration_test/ssot_smoke.dart) で32回の製品CLIを実行した。下表の拒否ケースも期待どおりの失敗として成功数に含む。

| 操作 | 期待結果と観測結果 |
| --- | --- |
| close --allの不正timeout / 未知option | 終了2、INVALID_ARGUMENT、session:null。runtime未生成 |
| connect → snapshot | 接続成功、tap_buttonの公開ref取得 |
| ref / selector / 0ms wait | 成功。poll間隔50 / 1000は受理 |
| ref waitのpoll間隔49 / 1001 | 終了2。その後同じrefでget成功 |
| find tap → confirm | 保留時は操作せず、confirm後カウンタ1 |
| batchのfind click → confirm | batch全体を1回承認しカウンタ2 |
| workflowのtap / wait / snapshot → confirm | workflow全体を1回承認しカウンタ3 |
| 各confirmの再利用 | 3回とも終了2、INVALID_ARGUMENT |
| deny tap policyでfind click | 終了1、ACTION_DENIED。カウンタ3のまま |
| close → session list → 再接続 | sessionは空、外部起動アプリは存続、カウンタ3 |
| close --all | 終了0、session:null、1 sessionのclose結果 |

最初の接続試行は、exampleが背面にある状態でTIMEOUT / not_sentだった。UI操作は送信されていない。アプリを前面に戻し、先のruntimeをcloseし、新しいruntimeで上記32呼び出しを最初から実行した。

## CLI実測抜粋

実行ファイルはリポジトリルート基準に変換した。共通のJSON・timeoutオプションを明記し、sessionは環境変数 `MARIONETTE_AGENT_SESSION=ssot-review` で選択した。専用runtimeと入力ファイルの外部pathは `<verification-directory>`、承認IDは `<confirmation-id>` に置換する。stdin入力なし。stderrはclose系以外は空。認証URIは掲載しない。

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json close --all --timeout 0
```

入力は引数のみ。終了2、stdout全量:

```json
{"schemaVersion":1,"ok":false,"session":null,"data":null,"error":{"code":"INVALID_ARGUMENT","message":"Duration is out of range","hint":"Run marionette-agent --help","outcome":"not_sent"}}
```

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --timeout 30000 --confirm-actions tap find key tap_button tap
```

入力は引数のみ。終了1、stdout全量（ID置換）:

```json
{"schemaVersion":1,"ok":false,"session":"ssot-review","data":null,"error":{"details":{"confirmationId":"<confirmation-id>","command":"find"},"code":"CONFIRMATION_REQUIRED","message":"Action requires confirmation","hint":"Use confirm <id> or deny <id> in this session","outcome":"not_sent"}}
```

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --timeout 30000 confirm '<confirmation-id>'
```

直前の結果から取得したIDを入力。初回は終了0、stdout全量:

```json
{"schemaVersion":1,"ok":true,"session":"ssot-review","data":{"requiresSnapshot":true},"error":null}
```

同じ引数で再実行すると終了2、stdout全量:

```json
{"schemaVersion":1,"ok":false,"session":"ssot-review","data":null,"error":{"code":"INVALID_ARGUMENT","message":"Confirmation is absent or expired","hint":null,"outcome":"not_sent"}}
```

batchとworkflow実行後:

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --timeout 30000 get text --key tap_result
```

入力は引数のみ。終了0、stdout全量:

```json
{"schemaVersion":1,"ok":true,"session":"ssot-review","data":{"text":"Tap count: 3"},"error":null}
```

```sh
dart packages/marionette_agent/bin/marionette_agent.dart --json --timeout 30000 close --all
```

入力は引数のみ。終了0、stdout全量:

```json
{"schemaVersion":1,"ok":true,"session":null,"data":{"closed":true,"sessions":[{"schemaVersion":1,"ok":true,"session":"ssot-review","data":{"closed":true},"error":null}]},"error":null}
```

stderr全量（単一closeも同じ診断）:

```text
[INFO] VmServiceConnector: Disconnecting from VM service
```

## エビデンスと終了処理

製品CLIのscreenshotで取得した2枚を開いて確認した。`before-confirm.png` はTap count: 0、`after-operations.png` はTap count: 3。PRに2枚を添付する。画像は画面変化の証拠であり、切断失敗・null入力の証拠は回帰テストで補う。

終了時は両runtimeのdaemon metadata/socketが消え、session一覧が空であることを確認した。検証用runnerは終了0、使用Simulatorは開始前のShutdownへ戻し、私有VM URIファイルを削除して利用記録を解放した。他の起動中Simulatorは操作していない。

## 人間による再現

1. exampleを専用iOS Simulatorで新規起動し、ControlsのTap count: 0を確認する。Flutterのdebug VM service URIを取り直し、私有ファイルに保存する。専用runtime・sessionを用意する。
2. CLIでconnectし、snapshotからtap_buttonの新しいrefを取得する。ref / selector / 0ms waitを実行する。poll間隔49 / 1001は拒否され、直前refのgetは成功することを確認する。
3. 上記find tapをconfirm-actions付きで実行する。承認前0、confirm後1、同じIDの再利用はINVALID_ARGUMENTとなることを確認する。
4. smoke fixtureと同じ内容のbatch（find click、wait 0、get tap_result）とworkflow（tap、wait exists、snapshot）を用意する。それぞれconfirmして、カウンタが2、3と増えることを確認する。
5. `deny:["tap"]` のpolicyを設定しfind clickを実行する。ACTION_DENIEDとなり、画面が3のままであることを確認する。
6. 単一close、session list、同じ外部アプリへのconnect、全体closeを実行する。一覧は空、再接続後は3、全体closeのsessionはnullとなることを確認する。
7. 接続不要のclose --allに不正timeout・未知optionを渡し、session:nullのINVALID_ARGUMENTと終了2を確認する。所有した環境だけを終了し、認証URIを削除する。

自動再現時はfresh exampleと書込み可能な私有ディレクトリ内のevidenceフォルダを先に用意する。`MARIONETTE_TEST_PRIVATE` にそのディレクトリ、`MARIONETTE_TEST_VM_URI_FILE` にURIファイルを指定してsmokeを実行する。fixture、CLIログ、画像はその私有ディレクトリに保存される。

- [ ] 人間が変更内容と画面を確認した

Android/Webの実環境検証は今回実施していない。
