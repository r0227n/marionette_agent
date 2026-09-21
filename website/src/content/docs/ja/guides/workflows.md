---
title: 手順をworkflowにする
description: 観測と操作をJSON・YAMLにまとめ、検証してから順番に実行する。
---

手動で確認した操作を繰り返すなら、workflowで名前付きの手順にします。1つのsession内で各stepを順番に実行し、別の要求がstep間へ割り込むのを防ぎます。

## 小さな手順を書く

次の内容を`observe-edit.yaml`として保存します。[同じファイルをダウンロード](/marionette_agent/examples/observe-edit.yaml)することもできます。対象はControls画面のexampleです。

```yaml
schemaVersion: 1
name: observe-edit
steps:
  - id: before
    action: snapshot
  - id: enter-text
    action: fill
    target: { key: text_input }
    text: { literal: hello }
  - id: after
    action: snapshot
```

`id`は手順内で一意にします。`target`はselectorで指定し、snapshotから発行されたrefや座標は使いません。

## 接続前に検証する

```sh
marionette-agent workflow validate observe-edit.yaml --json
marionette-agent workflow schema fill --json
```

`validate`はファイルの構造と意味制約を検証します。UI要素の存在や可視性は、実行時の確認です。`schema`でCLIに同梱された実際の入力定義を取得できます。

## 接続済みsessionで実行する

[クイックスタート](/marionette_agent/ja/getting-started/quick-start/)で接続した`docs-demo`を使う例です。sessionを閉じた場合は、現在のURIで接続し直してください。

```sh
marionette-agent --session docs-demo workflow run observe-edit.yaml --json
```

この手順は最後にsnapshotを取得するので、成功結果の`finalSnapshot`から入力後の画面を確認できます。その後に操作がなければ、このsnapshotのrefを続くCLIでも使えます。

## 使えるstep

| action             | 用途                           |
| ------------------ | ------------------------------ |
| `snapshot`         | 観測結果を更新する             |
| `tap`              | selectorで指定した要素をタップ |
| `fill`             | 入力欄を文字列で置換           |
| `swipe` / `scroll` | 指定方向へジェスチャー         |
| `wait`             | 要素の出現・消失を待つ         |

1〜100 stepを記述できます。条件分岐、loop、shell実行、他workflowのinclude、画像保存はworkflow v1に含まれません。

## 入力値を外に分ける

再利用したい文字列は`inputs`で`type: string`として定義し、stepの値を`{ input: name }`形式で参照できます。実値は`--inputs`でJSON/YAMLファイルから渡します。環境変数やshell式の展開は行いません。

通常の`validate`はtemplate検証です。必要な入力値まで確認するには`--inputs`または`--check-inputs`を付けます。`run`は常に入力値のbindingまで検証します。

## 途中で失敗したら

最初の失敗で停止します。既に完了した操作の取り消しや、自動retry、途中再開はありません。応答を受信できた場合はエラー詳細の進捗を確認し、実際の画面を観測してから復旧方法を決めます。

`--timeout`はファイル読込、検証、queue待ち、全stepを含む期限です。stepごとに時間がリセットされるわけではありません。

[workflowファイル仕様](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/workflow-file-spec.ja.md)に全field、parser制限、上限、binding、失敗時の進捗を定義しています。
