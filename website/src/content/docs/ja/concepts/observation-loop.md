---
title: 観測・操作・確認の流れ
description: snapshotとrefを使い、画面の変化を確認しながら操作を進める。
---

1回の操作を「観測する → 対象を決める → 操作する → 結果を観測する」の単位で考えます。これが画面と手順のずれを見つける基本です。

## snapshotで現在の画面を読む

```sh
marionette-agent snapshot
marionette-agent snapshot --interactive --compact
marionette-agent snapshot --key tap_button --json
```

snapshotには、観測できた要素のtype、text、key、bounds、visibleなどが含まれます。完全なWidgetツリーではなく、未構築のリスト項目も含みません。取得できない属性があることを前提に読みます。

`--interactive`は操作候補に絞り、`--compact`は表示情報を減らします。`--depth`で観測の深さを指定することもできます。key・text・type・identifierによるfilterは1つだけ指定できます。

## refで対象を選ぶ

操作可能な要素に付く`@e1`のような参照をrefと呼びます。次は構文例です。実行時は、直前のsnapshotに表示されたrefに置き換えます。

```sh
marionette-agent tap @e1
marionette-agent snapshot
```

**新しいsnapshotやUI操作の後は、以前のrefを使いません。** refはsession内の観測に紐づき、再接続・切断でも失効します。操作の送信後にエラーになった場合も、古いrefを再利用しないでください。

## 結果はアプリの状態で確かめる

CLIが操作を完了しても、アプリが期待する画面へ遷移したかは別に確認します。要素の出現を待ち、最新のsnapshotを取得する例です。

```sh
marionette-agent tap --key about_tab
marionette-agent wait --key about_content --timeout 5000
marionette-agent snapshot
```

`wait`は観測を繰り返します。成功しても新しいrefは発行しないため、次の操作の前にsnapshotを取得します。一定時間寝るだけの待機より、表示されるはずの要素を条件にすると手順の目的が明確になります。

## 失敗したときの判断

通信断やタイムアウトで操作結果が`unknown`になった場合、アプリ側では操作済みかもしれません。明示的に再接続し、画面を見直してから次の操作を決めます。CLIはUI操作を自動で再送しません。

JSONの`ok`、`error.code`、`error.outcome`を使った分岐は[出力とエラー](/marionette_agent/ja/reference/output/)を参照してください。
