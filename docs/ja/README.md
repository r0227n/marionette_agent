# 日本語の補足ドキュメント

[English](../README.md)

導入・操作方法は[日本語ドキュメントサイト](https://r0227n.github.io/marionette_agent/ja/)に集約しています。公開前やオフラインでは[サイト原稿](../../website/src/content/docs/ja/getting-started/overview.md)を読むか、[ローカルプレビュー](../../website/README.md)を使ってください。

このディレクトリには、サイトで扱わない詳細仕様と開発手順だけを置きます。英語版は`docs/`直下です。

| 補足 | 読むタイミング | English |
| --- | --- | --- |
| [製品仕様](SPEC.ja.md) | CLI契約、対象範囲、エラー、寿命、MCP、録画の仕様を調べる | [Product specification](../SPEC.md) |
| [アーキテクチャ](ARCHITECTURE.ja.md) | モジュールの責務、依存方向、実装境界を確認する | [Architecture](../ARCHITECTURE.md) |
| [CLI実行の詳細](cli-reference.ja.md) | 出力制限、MCP、Skills、画像保存・録画の厳密な挙動を調べる | [CLI runtime details](../cli-reference.md) |
| [追加操作の制約](cli-parity.ja.md) | provider、find、キーボード、差分、batch、policyを使う | [Advanced operation details](../cli-parity.md) |
| [workflowファイル仕様](workflow-file-spec.ja.md) | schema、binding、上限、失敗時の進捗を実装する | [Workflow file reference](../workflow-file-spec.md) |
| [headlessガイドの移動先](headless.ja.md) | サイトへ移した管理起動・手動セットアップを読む | [Headless guides](../headless.md) |
| [コマンド実装契約](command-contract.ja.md) | CLI handlerやbackend adapterを開発する | [Command implementation contract](../command-contract.md) |
| [実環境検証](runtime-verification.ja.md) | exampleアプリによるCLI受入確認を再現する | [Runtime verification](../runtime-verification.md) |
| [文書の配置・翻訳方針](documentation.ja.md) | 文書の追加先を決め、日英を更新する | [Documentation policy](../documentation.md) |

従来のファイル名は既存リンクから詳細へ到達できるよう維持しています。導入、基本コマンド一覧、クイックスタート、管理されたlaunchの重複説明は削除しました。

## 内部文書

上記の製品仕様とアーキテクチャは、現行の開発契約として日英を維持します。調査・ADR・[Agent運用文書](../agents/)は別の用途を持ち、この日英対応の対象外として日本語のまま残る場合があります。過去の調査記録を現行の利用ガイドとして扱いません。
