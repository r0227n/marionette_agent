---
title: 出力とエラーを読む
description: JSON包絡、終了コード、操作結果のoutcomeを使って次の処理を決める。
---

人が読む場合は通常のテキスト出力、スクリプトでは`--json`を使います。結果はstdout、診断はstderrへ出ます。

## JSONの基本形

通常コマンドは成功・失敗とも共通の包絡を返します。次は形式を示す例です。

```json
{
  "schemaVersion": 1,
  "ok": true,
  "session": "demo",
  "data": { "requiresSnapshot": true },
  "error": null
}
```

`ok`で成否を判定し、成功時は`data`、失敗時は`error`を読みます。sessionに依存しないコマンドの`session`はnullです。`requiresSnapshot: true`は、次の判断に新しい観測が必要なことを示します。

```json
{
  "schemaVersion": 1,
  "ok": false,
  "session": "demo",
  "data": null,
  "error": {
    "code": "STALE_REF",
    "message": "Target changed",
    "hint": "Run snapshot again",
    "outcome": "not_sent"
  }
}
```

`message`の文言へ依存する分岐より、`code`と`outcome`を使います。`hint`は次に行う確認の手掛かりです。

## outcomeの意味

| outcome    | 意味                       | 次の判断                               |
| ---------- | -------------------------- | -------------------------------------- |
| `not_sent` | 対象操作は送信されていない | 引数・接続・対象を修正する             |
| `failed`   | 失敗が確定している         | エラー原因と現在のアプリ状態を確認する |
| `unknown`  | 送信後の結果を確定できない | 再接続・再観測して実際の状態を確認する |

特に`unknown`では「操作されなかった」と仮定しません。送信済みの購入・保存・画面遷移などを無条件に繰り返さないよう、現在の状態から再判断します。

## 終了コード

| 値  | 主な分類                                                                         |
| --- | -------------------------------------------------------------------------------- |
| 0   | 成功                                                                             |
| 2   | 引数不正: `INVALID_ARGUMENT`                                                     |
| 3   | 接続: `NOT_CONNECTED`、`SESSION_CONFLICT`、`CONNECTION_LOST`                     |
| 4   | 対象: `TARGET_NOT_FOUND`、`AMBIGUOUS_TARGET`、`STALE_REF`、`UNRESOLVABLE_TARGET` |
| 5   | 期限: `TIMEOUT`                                                                  |
| 6   | 機能不足: `UNSUPPORTED_CAPABILITY`                                               |
| 1   | その他: `BACKEND_ERROR`、`IO_ERROR`、policy拒否など                              |

## unknownと空値を区別する

`is visible`・`is enabled`・`is checked`では、`known`と`value`を読みます。観測できなかった場合の形式例です。

```json
{ "known": false, "value": null }
```

これは「見えない」「無効」「未チェック」を意味しません。textのnullと空文字、boundsのnullとゼロも区別します。

## 個別の出力契約

- `doctor`は検査の実行が成功すると`ok: true`でも、不適合や未確認があればprocessの終了コードが1になります。`data.exitCode`と各checkを確認します。
- `skills`は同梱コンテンツ配信用の独自形式です。
- 稼働中の`mcp`のstdoutはMCPメッセージ専用です。通常のCLI JSONとして読まないでください。
- `--max-output`は結果全体のサイズ上限ではありません。省略metadataとrefの有効性も確認します。

復旧の手順は[トラブルシューティング](/marionette_agent/ja/reference/troubleshooting/)にまとめています。
