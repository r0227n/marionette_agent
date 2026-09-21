---
title: できることと対応範囲
description: marionette-agentを使うための前提と、CLI・Flutterアプリ・実行環境の関係。
---

marionette-agentは、起動したFlutterアプリの状態を読み取り、対象を指定して操作する道具です。テスト手順の調査、エージェントによるUI操作、操作後の状態確認に使います。

CLIはDart VM Serviceを通じてアプリ内のMarionette bindingと通信します。アプリを観測できる状態に準備してから、接続を開始します。

## 最初に揃えるもの

| 要素                       | 必要なもの                                        |
| -------------------------- | ------------------------------------------------- |
| CLIを動かすホスト          | macOS。Linux・Windowsホストは現在の対応範囲外     |
| CLIのビルド                | Dart 3.13.2以上・4.0.0未満とFlutter SDK           |
| 操作対象                   | `marionette_flutter` 0.6.0を初期化したdebugアプリ |
| 手動起動したアプリへの接続 | その実行のVM Service URI                          |
| iOSで最初の確認            | Xcode、利用可能なiOS Simulator、同梱example       |

同梱exampleの検証環境はFlutter 3.47.2です。まずこの組合せで接続を確認すると、SDK差とアプリ側の問題を切り分けやすくなります。

## 何を操作できるか

- 画面の観測、要素のtext・bounds・状態の取得。
- タップ、入力、スワイプ、スクロール、条件待機。
- sessionごとの接続管理、JSON出力、workflowの順次実行。
- 画像・動画の保存、MCP経由のツール呼出し。

追加の入力・状態取得には、アプリ側の補助providerが必要なものがあります。[アプリへの組込み](/marionette_agent/ja/getting-started/app-integration/)で準備を確認してください。

## 実行環境を選ぶ

通常の導入では、iOS Simulator上のexampleを手動起動して接続します。`launch`を使うとtester・iOS・Android・macOS・Webを明示して起動し、そのsessionへ接続できます。

testerはFlutter共通UIの反復確認に向いています。OSの権限、ネイティブプラグイン、ブラウザー固有の振る舞いを確認する場合は、対応する実行環境を選びます。詳細は[headless実行](/marionette_agent/ja/guides/headless/)を参照してください。

## 操作結果の読み方

操作の成功応答は、業務上の目的が達成されたことまで保証しません。ボタンを押したら、画面をもう一度観測して期待する値や要素を確認します。遅延リストの未構築項目や、観測できなかった属性をsnapshotから推測しないでください。

このサイトは開発版の仕様を説明しています。各ページ上部に対象バージョンとコミットを表示しています。[インストール](/marionette_agent/ja/getting-started/installation/)から始めてください。
