---
title: 互換性とサポート
description: 1.xで保護する公開契約と対応環境。
---

以下の1.xの公開面にセマンティックバージョニングを適用します。現在のソースからの導入方法を維持し、pub.dev公開は無効のままです。

## 1.xで安定させる範囲

- 文書化したコマンド名、flag、alias、受け付ける引数、既定値、設定と環境変数の優先順位。削除や意味の変更はmajor版の変更です。任意の新コマンドやoptionはminorで追加できます。
- 文書化したJSONのfield名、型、nullとunknownの意味、必須field。既存のerror `code`、`outcome`、終了コードの意味を維持します。任意field、コマンド、capability、新error codeはminorで追加できます。クライアントは未知fieldを無視し、未知codeも終了分類とoutcomeを使って失敗として扱ってください。
- stdoutはコマンド結果、stderrは診断です。通常コマンドの`--json`は1件のJSON結果を出します。文書化した`skills`形式とMCPのstdoutプロトコルは別契約なので、通常envelopeを当てはめません。人間向けの文言、空白、診断、error message/hintの文章は変更できます。textを解析せずJSONを使ってください。
- Workflow schema version 1と、アプリ側utilの文書化した公開関数・service-extension payload。必須field、型、意味の変更や削除にはmajor版か、明示的に交渉する新schemaが必要です。

patchは既存契約に合わせる修正、minorは互換性のある機能追加です。majorでは影響するflag、JSON/error、CLI/utilの組合せを含む移行手順をCHANGELOGと日英文書に示します。セキュリティ修正で契約を破る必要がある場合は、例外と移行方法を説明します。

## CLI・daemon・アプリの版

CLIと`marionette_agent_util`は**同じリリースcheckout**から使用してください。これがサポートする組合せで、任意の異なるリリースの混在は保証しません。現在の上流は`marionette_mcp: 0.6.0`と`marionette_flutter: 0.6.0`です。stock bindingは基本capabilityを、任意のutil providerは追加capabilityを提供します。不足extensionは推測による代替でなく`UNSUPPORTED_CAPABILITY`を返します。

CLI package version、JSON `schemaVersion`、内部IPC `protocolVersion`、workflow schema version、app extension versionは独立しています。この版ではJSON/workflowは1、IPCは7、app extensionは1を維持します。内部IPCは1.xの途中でも変更できます。更新前にsessionをcloseし、新binaryでdaemonを新規起動してください。snapshot、session、再接続、変更操作をまたいでrefを使い回さないでください。

## 対応環境と問い合わせ

CLIの対応ホストはmacOSで、検証の基準はmacOS arm64、Flutter 3.47.2、Dart 3.13.2です。SDK制約はDart >=3.13.2 <4.0.0ですが、全SDK組合せの保証ではありません。Linux/Windowsホストは対応しません。iOS SimulatorにはXcode、AndroidにはSDK/adb、macOSとChromeには各runtimeが必要です。testerはFlutter UI向けで、native pluginやOS動作の確認には使えません。端末録画の権限と範囲はbackendごとに異なり、iOS実機録画には対応しません。

公開後は最新1.xへのbest-effort修正を対象とし、応答時間や有償サポートのSLAは約束しません。通常の不具合は秘匿済みの再現手順、版、ホスト、対象runtimeを添えて[GitHub Issues](https://github.com/r0227n/marionette_agent/issues)へ報告してください。脆弱性の報告もこの**公開**Issuesを窓口とし、秘匿済みの概要だけを投稿してください。秘密情報・個人情報・認証トークン・悪用可能な詳細は投稿しません。機微な再現詳細を共有する前に、メンテナーへ非公開での追加連絡の調整を依頼してください。非公開窓口は事前に約束せず、GitHubの非公開報告も現在無効です。報告方法と安全な利用条件は[SECURITY.md](https://github.com/r0227n/marionette_agent/blob/develop/SECURITY.md)にあります。復旧時は[出力](/marionette_agent/ja/reference/output/)と[トラブルシューティング](/marionette_agent/ja/reference/troubleshooting/)を参照してください。
