---
title: sessionと接続の寿命
description: 接続と観測をsessionで分離し、connectとlaunchの終了動作を理解する。
---

sessionは、1つのアプリへの接続と観測結果を保持する単位です。コマンド間の接続はローカルdaemonが管理するため、シェルから1コマンドずつ呼び出せます。

## 名前付きsessionを選ぶ

次の`VM_URI`には、起動済みアプリのVM Service URIを設定します。

```sh
marionette-agent --session demo connect "$VM_URI"
marionette-agent --session demo snapshot
marionette-agent --session demo session show
marionette-agent session list
```

session名は英数字で始まる英数字・`_`・`-`で、最大64文字です。省略時は`default`です。環境変数`MARIONETTE_AGENT_SESSION`で既定値を指定することもできます。

同じsessionの操作は順番に処理されます。異なるsessionは独立しますが、同じ正規化URIを複数のsessionが所有することはできません。同じsessionを別のURIへ接続する場合は、先に閉じます。

## connectとlaunchの違い

| 接続方法  | CLIが所有するもの              | close時の動作                        |
| --------- | ------------------------------ | ------------------------------------ |
| `connect` | 既に起動したアプリへの接続     | 接続を閉じる。アプリは継続           |
| `launch`  | 起動したアプリ・実行環境と接続 | 録画を確定し、所有アプリ・端末を終了 |

この違いは後片付けの範囲に影響します。手動起動したSimulatorを閉じる目的で`close`を使わないでください。

## 接続を閉じる

```sh
marionette-agent --session demo close
```

存在しないsessionを閉じても成功します。全sessionを終了する場合は、明示的な`--session`を付けずに実行します。

```sh
marionette-agent close --all
```

`close --all`は同じdaemonの他のsessionも終了するため、並行作業中は個別closeを使います。

## 接続が失われたら

通信断、アプリ終了、daemon再起動では、既存refを使えなくなります。外部起動したアプリなら現在のURIで明示的に再接続し、新しいsnapshotを取得します。

daemonのidle期限は既定1時間で、起動時に確定します。全要求がidleになった後に期限へ達すると、録画と接続を終了します。長い録画を行う場合もidle設定を確認してください。

## 並行作業を分離する

sessionだけでなく、端末・アプリcheckout・出力先も分けます。daemonまで分けたい場合は`--namespace`または`MARIONETTE_AGENT_RUNTIME_DIR`を使います。runtimeは短い私有パスとし、Unix socketのパス上限80 UTF-8 bytesに注意してください。

詳しい既定値は[設定リファレンス](/marionette_agent/ja/reference/configuration/)にあります。
