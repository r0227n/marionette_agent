---
title: 対象の選び方
description: ref・key・text・typeを使い分け、曖昧な対象や古い参照を避ける。
---

対話的な操作ではsnapshotのref、繰り返す手順ではアプリに付けた一意なkeyが便利です。どの指定方法でも、操作時に対象が解決できる必要があります。

| 指定           | 使いどころ               | 注意点                                                                 |
| -------------- | ------------------------ | ---------------------------------------------------------------------- |
| `@e1`          | 直前に見つけた要素を操作 | 最新の同じsessionで発行されたrefを使う                                 |
| `--key`        | 固定手順やworkflow       | 観測された対象のkeyと完全一致                                          |
| `--text`       | 表示文言から探す         | 大文字小文字を含め完全一致。全ての表示textが操作用に使えるとは限らない |
| `--type`       | widget種別から探す       | 操作には一意な対象が必要                                               |
| `--identifier` | identifierによる指定     | 固定binding 0.6.0の操作matcherでは未対応                               |

ref・selector・座標を混ぜず、そのコマンドが受理する方法から1つを選びます。

## keyを使って操作する

```sh
marionette-agent tap --key tap_button
marionette-agent fill --key text_input 'hello'
marionette-agent get text --key tap_result
```

selectorは操作時の観測に対して解決されます。対象が0件なら`TARGET_NOT_FOUND`、複数なら`AMBIGUOUS_TARGET`です。複数の候補から勝手に1つが選ばれることはありません。

## 観測のfilterと操作のselector

```sh
marionette-agent snapshot --text 'Save'
marionette-agent get count --text 'Save'
```

この結果から、`Save`というtextが観測されているかを調べられます。ただし、観測できたtextと操作matcherが一致するとは限りません。`get count`の件数も操作可能性の保証ではありません。

`--identifier`によるsnapshot filterは、identifierを観測できれば絞り込めます。identifierを使った操作の対応状況とは別です。

## 追加の検索

補助providerを使うと、label・placeholder・roleなどで検索できます。次はexampleのAdvanced画面での例です。

```sh
marionette-agent tap --key advanced_tab
marionette-agent find label 'Editable' focus
marionette-agent snapshot
```

`find first`・`find last`・`find nth`による順序指定もできますが、画面構造への依存が増えます。固定手順にはkeyを優先すると変更の影響を抑えられます。

## 座標を使う場合

```sh
marionette-agent tap --x 120 --y 240
```

座標はFlutter論理ピクセルです。画像の物理ピクセルをそのまま使わないでください。画面サイズや配置が変わる手順では、要素を指定する方法の方が意図を保ちやすくなります。
