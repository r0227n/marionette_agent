---
title: コマンド一覧
description: 接続、観測、操作、ファイル保存、管理の目的別にCLIの構文を調べる。
---

表中の`TARGET`は、直近のrefまたは`--key`・`--text`・`--type`などのselectorを表します。具体的な選び方は[対象の指定](/marionette_agent/ja/concepts/targets/)を参照してください。共通オプションはコマンドの前後で指定できます。

## 接続と起動

| 構文                                 | 結果・前提                                                                                                        |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `connect URI`                        | 起動済みdebugアプリへ接続。HTTP(S) URIもWS(S)へ正規化                                                             |
| `launch PROJECT --platform PLATFORM` | ビルド・起動・接続・最初の観測。platform固有オプションは[起動ガイド](/marionette_agent/ja/guides/headless/)を参照 |
| `session list`                       | daemonが持つsessionの一覧。daemon不在なら空一覧                                                                   |
| `session show`                       | 選択sessionの状態と秘匿済み接続先                                                                                 |
| `close`                              | 選択sessionを終了。launchしたアプリも終了                                                                         |
| `close --all`                        | daemonの全sessionを終了。明示`--session`との併用不可                                                              |

## 観測と状態照会

| 構文                                         | 結果・前提                                             |
| -------------------------------------------- | ------------------------------------------------------ |
| `snapshot`                                   | 新しい観測とref。以前のrefは失効                       |
| `snapshot --key KEY`                         | 観測を完全一致でfilter。text・type・identifierも選択可 |
| `snapshot --interactive --compact --depth N` | 操作候補・表示情報・観測深度を調整                     |
| `get text TARGET`                            | 表示text。未取得はnull                                 |
| `get box TARGET`                             | boundsと単位`flutter_logical_pixels`。未取得はnull     |
| `get count SELECTOR`                         | 観測候補の件数。ref不可、0件も成功                     |
| `get value TARGET`                           | 型付き入力値。対応providerが必要                       |
| `is visible TARGET`                          | 可視状態をknown/valueで返す                            |
| `is enabled TARGET` / `is checked TARGET`    | 対応providerによる状態。未観測はunknown                |
| `logs`                                       | 収集済みログを取得。継続購読ではない                   |

通常のget・isは観測を読み、成功時に新しいrefを発行しません。`unknown`をfalseとして扱わないでください。

## タップ・入力・ジェスチャー

| 構文                                                  | 動作                                  |
| ----------------------------------------------------- | ------------------------------------- |
| `tap TARGET` / `click TARGET`                         | 同じタップ操作                        |
| `tap --x X --y Y`                                     | Flutter論理座標をタップ               |
| `fill TARGET TEXT`                                    | 入力全体を置換。空文字でクリア        |
| `swipe TARGET DIRECTION --distance N`                 | 対象を起点に指を移動。距離の既定は200 |
| `swipe --start-x X --start-y Y --end-x X2 --end-y Y2` | 始点から終点へのジェスチャー          |
| `scroll TARGET DIRECTION --distance N`                | 指定領域へのスクロールジェスチャー    |

directionは`left`・`right`・`up`・`down`で、**指の移動方向**です。コンテンツの到達位置やページ切替は次のsnapshotで確認します。

## 補助providerを使う操作

以下は対応するアプリ側providerが必要です。exampleのAdvanced画面で試せます。

| 構文                                              | 動作                                                    |
| ------------------------------------------------- | ------------------------------------------------------- |
| `dblclick TARGET`                                 | 2回のタップ                                             |
| `focus TARGET` / `hover TARGET`                   | 入力focus／合成mouseイベント                            |
| `type TARGET TEXT`                                | 選択範囲に挿入。無効な選択なら末尾に追加                |
| `check TARGET` / `uncheck TARGET`                 | Checkbox・Switchを希望する状態にする                    |
| `select TARGET VALUE`                             | DropdownButtonの文字列値を選択                          |
| `scrollintoview TARGET`                           | 構築済み要素へensureVisible。未構築項目の探索は行わない |
| `drag FROM_REF TO_REF`                            | 2つの対象間でtouchジェスチャー                          |
| `drag --from-key KEY --to-key KEY2`               | keyで指定した2対象間のdrag                              |
| `press KEYS`                                      | キーを押して離す。例: `Control+A`                       |
| `keydown KEY` / `keyup KEY`                       | 1つのキーを保持／解放                                   |
| `keyboard press KEYS`                             | focus先へキー入力                                       |
| `keyboard type TEXT` / `keyboard inserttext TEXT` | focus先のEditableTextへ文字列を挿入                     |
| `clipboard read` / `clipboard write TEXT`         | clipboardの読み書き                                     |
| `clipboard copy` / `clipboard paste`              | focus先でコピー／ペースト                               |

## 検索と待機

`find`ではrole・label・placeholder・text・key・identifier・typeを指定できます。`--exact`で完全一致、roleでは`--name`も指定できます。必要に応じて検索後のactionと入力値を続けます。

```sh
marionette-agent find label 'Editable' focus
marionette-agent find key advanced_input type 'hello'
marionette-agent wait --key about_content --timeout 5000
marionette-agent wait --key loading --state gone --poll-interval 100
```

`find first SELECTOR`・`find last SELECTOR`・`find nth INDEX SELECTOR`による選択にも対応します。

`wait`の既定stateは`exists`で、一意かつ`visible != false`なら成功します。`gone`は一致が0件になるまで待ちます。poll間隔は50〜1,000ms、既定100msです。`wait REF`や`wait MILLISECONDS`も使用できます。成功後に新しいsnapshotが必要かは結果の`requiresSnapshot`を確認します。

## 画像・動画・差分

| 構文                                                    | 用途                                                |
| ------------------------------------------------------- | --------------------------------------------------- |
| `screenshot [PATH]`                                     | 画像を新規保存                                      |
| `screenshot TARGET [PATH]`                              | 対象領域の画像                                      |
| `screenshot --annotate [PATH]`                          | ref注釈付き画像。providerと有効snapshotが必要       |
| `record start PATH --platform PLATFORM [--device ID]`   | 動画開始。Flutter描画はdevice不要                   |
| `record restart PATH --platform PLATFORM [--device ID]` | 現在の録画を確定後、新規開始                        |
| `record status` / `record stop`                         | 状態取得／確定して停止                              |
| `diff snapshot --baseline PATH`                         | 保存したsnapshotとの差分                            |
| `diff screenshot --baseline PATH`                       | 保存画像との差分。`--threshold`・`--output`も使用可 |

保存条件とプラットフォーム差は[画像と動画](/marionette_agent/ja/guides/capture/)を参照してください。

## 自動化・設定・管理

| 構文                                           | 用途                                                    |
| ---------------------------------------------- | ------------------------------------------------------- |
| `workflow schema [ACTION]`                     | 同梱schemaを取得                                        |
| `workflow validate PATH` / `workflow run PATH` | workflowの検証／実行                                    |
| `batch PATH`                                   | JSONのargv配列を順次実行。共通オプションはbatch側に指定 |
| `state save PATH` / `state load PATH`          | 接続URIだけを私有ファイルへ保存／再接続                 |
| `confirm ID` / `deny ID`                       | 保留中の操作を承認／拒否                                |
| `device list --platform ios`                   | 利用可能なiOS端末。androidも指定可                      |
| `doctor`                                       | ローカル環境診断。`--probe-uri`で接続先も照会           |
| `doctor --quick` / `--offline` / `--fix`       | 検査を限定／VM probe省略／所有runtimeのmode修復         |
| `install DIRECTORY` / `upgrade DIRECTORY`      | ローカルソースからバイナリとSkillsを配置／更新          |
| `skills list` / `get` / `path`                 | 同梱ガイドを参照                                        |
| `mcp --tools PROFILES`                         | stdio MCPサーバー                                       |
| `--help` / `--version`                         | 接続なしで構文／版を確認                                |

batchは最初の失敗で止まり、接続寿命の変更、録画、ファイル保存などは内包できません。操作ポリシーと状態ファイルの扱いは[設定](/marionette_agent/ja/reference/configuration/)を参照してください。
