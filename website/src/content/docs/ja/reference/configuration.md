---
title: オプションと設定
description: CLIの共通オプション、環境変数、設定ファイル、操作ポリシーを使う。
---

1回だけの設定はCLIオプション、繰り返す既定値は明示したJSONファイルで管理します。sessionとtimeoutには環境変数も使えます。

## 共通オプション

| オプション                      | 意味・既定値                                              |
| ------------------------------- | --------------------------------------------------------- |
| `--session NAME`                | session名。既定`default`。`--session-name`は別名          |
| `--timeout MS`                  | ファイル読込・queue待ち・実行を含む全体期限。既定30,000ms |
| `--json`                        | 結果をJSONで返す                                          |
| `--debug`                       | stderrに処理段階などの診断を出す                          |
| `--config PATH`                 | 共通オプションの既定値を持つJSONファイル                  |
| `--namespace NAME`              | daemonのruntimeを名前で分離                               |
| `--idle-timeout DURATION`       | daemon起動時のidle期限。既定1h、0で無効                   |
| `--content-boundaries`          | snapshot・logsのアプリ由来データを識別する境界情報        |
| `--max-output N`                | snapshot・logsの完全な項目に対する文字数予算              |
| `--screenshot-format png\|jpeg` | 保存形式。既定png                                         |
| `--screenshot-quality N`        | JPEG品質0〜100。既定90                                    |
| `--screenshot-dir PATH`         | path省略時の画像保存先。既存ディレクトリを指定            |
| `--restore PATH`                | 状態ファイルのURIへ接続してから実行                       |
| `--action-policy PATH`          | allow・deny・confirmを定めるJSON                          |
| `--confirm-actions LIST`        | 確認対象のコマンド名をcommaで追加                         |
| `--confirm-interactive`         | TTY上で確認を要求                                         |

同じオプションの重複は引数エラーです。`--timeout`には正の整数ms、`--idle-timeout`には`10s`・`3m`・`1h`のような単位付き値も使えます。稼働中daemonと異なるidle設定は要求送信前に拒否されます。

## 設定ファイルと優先順位

次を`agent.config.json`として保存します。

```json
{
  "session": "demo",
  "timeout": 10000,
  "json": true
}
```

```sh
marionette-agent --config agent.config.json snapshot
```

優先順は、明示CLI → session・timeoutの環境変数 → 明示config → 既定値です。configは正式なオプション名をkeyに使います。flagはbool、それ以外は文字列または整数で、未知keyは拒否されます。相対パスはCLIを呼んだディレクトリを基準にします。

| 環境変数                       | 用途                                         |
| ------------------------------ | -------------------------------------------- |
| `MARIONETTE_AGENT_SESSION`     | sessionの既定名                              |
| `MARIONETTE_AGENT_TIMEOUT_MS`  | timeoutの既定値                              |
| `MARIONETTE_AGENT_RUNTIME_DIR` | 私有runtimeディレクトリ                      |
| `MARIONETTE_AGENT_SKILLS_DIR`  | 同梱Skillsの読取元を既存ディレクトリで上書き |

空のsession・timeout環境値は「未設定」と扱われません。採用された空値は引数エラーです。明示CLIで上書きした環境値の値域は検証されません。

## 出力量と境界

```sh
marionette-agent snapshot --json --content-boundaries --max-output 4000
```

`--max-output`はUnicode code point単位で、完全な項目だけを先頭から残します。JSON包絡や画像のbyte数を制限するものではありません。`truncated`・`originalCount`・`omittedCount`で省略を確認でき、省略されたrefは操作に使えません。

`--content-boundaries`はアプリ文字列を観測データとして示す機能です。内容を無害化する機能ではありません。

## 操作を制限する

次はdragを拒否し、tapに確認を要求するpolicyです。

```json
{
  "default": "allow",
  "deny": ["drag"],
  "confirm": ["tap"]
}
```

`--action-policy`で指定するとsessionへ保持されます。優先順位はdeny → confirm → allowです。確認待ちは`CONFIRMATION_REQUIRED`とIDを返し、`confirm ID`または`deny ID`で処理します。保留は同一接続世代で5分間、1件だけです。

policyは明示的に置換できるため、OSの権限制御の代わりにはなりません。MCPでは`--confirm-interactive`と`--restore`を起動時に指定できません。

## 接続先を保存する

`state save`は認証URIを含む接続情報だけを0600の新規ファイルへ保存します。アプリ画面、入力値、ref、録画は保存しません。`state load`と`--restore`には現在ユーザーが所有する0600の通常ファイルが必要です。アプリが再起動してURIが変わった場合は取得し直します。
