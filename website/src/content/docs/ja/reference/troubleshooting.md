---
title: トラブルシューティング
description: 接続、古いref、曖昧な対象、provider不足、保存失敗を切り分ける。
---

まず「環境」「接続」「対象」「操作後の結果」のどこで止まったかを分けます。エラーの`code`と`outcome`を記録し、操作済みか不明な場合は再送前に画面を確認します。

## ローカル環境を調べる

```sh
marionette-agent doctor --json
marionette-agent doctor --quick --json
```

通常のdoctorは環境を読み取り、SDKやSimulatorをインストール・起動しません。checkごとの`status`・`reason`・`nextStep`を確認します。`--quick`はホスト・runtime・daemonに検査を絞ります。

起動済みアプリまで照会するには、その実行のURIを`VM_URI`へ設定します。

```sh
marionette-agent doctor --probe-uri "$VM_URI" --json
```

probeは独立した接続で確認し、通常sessionのrefは変更しません。bindingの登録が見つかることと、全操作が成功することは別です。

## 接続できない

| 症状               | 確認すること                                                               |
| ------------------ | -------------------------------------------------------------------------- |
| `NOT_CONNECTED`    | session名は同じか。connectまたはlaunchを行ったか                           |
| `CONNECTION_LOST`  | アプリやFlutter runnerが終了していないか。hot restart後のURIを使っているか |
| `SESSION_CONFLICT` | 同じURIを別sessionが使っていないか。launch対象projectが既に管理中でないか  |
| 起動時のtimeout    | 初回ビルド・端末起動に十分な期限か。アプリ依存を取得済みか                 |

外部アプリに再接続する場合は、現在のURIと対象sessionを明示し、snapshotを取り直します。URIファイルの古さを確認してから同じ手順を繰り返してください。

## 要素を選べない

**`STALE_REF`**: 新しいsnapshotを取得し、そこに返されたrefを使います。番号の推測や別sessionからの流用はできません。

**`AMBIGUOUS_TARGET`**: 同じtextやtypeの候補が複数あります。snapshotやget countで候補を調べ、一意なkeyで指定します。

**`TARGET_NOT_FOUND`**: 対象画面が表示されているか、keyの綴りが正しいかを確認します。遅延リストの未構築項目は、まずスクロールして観測できる状態にします。

**`UNRESOLVABLE_TARGET`**: 観測された表示textを、対応する操作対象へ安全に結び付けられません。keyなどの対応するselectorを使います。

## 機能が利用できない

`UNSUPPORTED_CAPABILITY`では、bindingと補助providerの登録状況を確認します。`--identifier`による操作は固定binding 0.6.0では未対応です。注釈撮影にはmapped screenshot provider、型付き状態や追加入力には対応するFlutter拡張が必要です。

## 画像・動画を保存できない

- 保存先の親ディレクトリと書込権限を確認し、既存ファイルと重ならない名前にする。
- `.jpg`を使う場合は`--screenshot-format jpeg`も明示する。
- Flutter描画の録画は接続済みsessionとffmpegを用意する。
- 端末画面の録画は正しいUDID・serial・display番号を使い、必要な画面収録許可を確認する。
- stopやcloseの期限に余裕を持たせ、動画確定中のprocessを途中で終了しない。

## 状況を報告する

CLIの版、対象コミット、ホスト・Flutter SDK・実行環境、認証情報を除いたコマンド、`code`と`outcome`、操作前後の状態を揃えます。`--debug`は処理段階の確認に使えます。URI・入力値・アプリの非公開情報を含むログや画像は共有前に取り除いてください。

[GitHubのIssue一覧](https://github.com/r0227n/marionette_agent/issues)で既存の報告を確認できます。
