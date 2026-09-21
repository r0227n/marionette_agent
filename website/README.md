# Documentation website

日英の利用者向け本文を新規執筆したAstro + Starlightサイトです。既存の`docs/ja/`は仕様を照合する参考資料として残し、サイトへコピー・取り込みはしていません。

## Local development

Node 24を使用します。以下は`website/`内で実行します。

```sh
npm ci
npm run dev
```

日本語は`http://localhost:4321/marionette_agent/ja/`、英語は`http://localhost:4321/marionette_agent/en/`です。検索はproduction buildに対して確認します。

```sh
npx playwright install chromium
npm run verify
npm run preview
```

`verify`は整形、Astroの型検査、日英のページ・コード例対応、ビルド、生成HTMLの内部リンク・アンカー・asset・SEO検査、ブラウザテストを実行します。ブラウザテストはproduction previewを自動起動します。失敗時のtraceと画面は`test-results/`、HTMLレポートは`playwright-report/`に保存します。

サイト以外のCLIコードを変更していない場合、サイト確認のためにSimulatorやDartテストを起動する必要はありません。CLIの仕様・実装を変更する場合はリポジトリの通常の検証規約に従います。

## Authoring

- `src/content/docs/ja/`と`en/`に同じ相対パスでページを追加します。本文のh1はfrontmatterのtitleから生成します。
- title・description・本文を両言語で揃えます。コード例は日英同一とし、説明を本文へ置きます。片方のコード例だけを変えると検証が失敗します。
- 公開用本文は利用者の目的から執筆し、コマンド・既定値・制約はCLI実装とSPECで照合します。ページが存在することだけでは翻訳の正確さや鮮度を保証しないため、両言語の意味をレビューします。
- 本文リンクは`/marionette_agent/<locale>/.../`を使用します。Starlightのサイドバー項目はlocaleなしのslugを指定します。
- サイトのorigin・baseは`site.config.mjs`、サイドバーは`astro.config.mjs`にあります。baseを変える場合は本文・テスト内のURLも更新し、全検証を行います。
- ダウンロード例は`public/examples/`に置きます。workflowガイドの例とダウンロードファイルの一致も検査します。
- `docs/`の内部仕様・開発運用・検証記録は公開サイトの原稿として読み込みません。

## GitHub Pages setup

想定URLは`https://r0227n.github.io/marionette_agent/`です。GitHub上の設定はファイルを追加するだけでは有効になりません。リポジトリ管理者は初回に次を設定します。

このリポジトリでは2026-09-21にSourceをGitHub Actionsへ設定し、`github-pages` environmentで`develop`からの公開を許可しました。初回のサイト公開はこのworkflowがdevelopへ入ってから行われます。別リポジトリへ移す場合は、下記の設定を改めて行ってください。

1. Settings → Pages → Build and deploymentでSourceに **GitHub Actions** を選ぶ。
2. Actionsの利用と、このworkflow内のGitHub公式Actionsが許可されていることを確認する。
3. `github-pages` environmentにbranch制限を設ける場合は`develop`を許可する。承認を必須にした場合は公開時にその承認を行う。
4. PRを`develop`へマージし、Documentation workflowのverifyとdeployが成功することを確認する。
5. 再公開する場合はActions → Documentation → Run workflowで **develop** を選ぶ。他ブランチからの手動実行は検証だけを行う。

PRでは検証のみ、developへの対象変更または手動実行では同じ検証を通過した`dist/`を1つのPages artifactとして公開します。deploy jobだけに`pages: write`と`id-token: write`を付け、PATは使いません。生成HTMLはcommitしません。

PR検証の対象はGitHubが用意するmerge commitです。実際の公開はdevelopのcommitからビルドし直し、全ページのバナーにpackage versionと対象SHAを表示します。package versionはCLIのpubspecから取得します。ローカルで未commitの変更を確認している場合、SHAはcheckoutのHEADを示します。

現在は開発版の公開です。安定版リリースへ切り替える際は、deploy元をrelease tagへ変更し、developからの自動公開を停止してから版表示と導入手順を揃えます。

## Human acceptance

日本語・英語のホームからクイックスタートへ進み、同じページのまま言語切替できることを確認します。検索で「録画」「STALE_REF」「recording」を調べ、選択言語の結果を開きます。スマートフォン幅ではメニュー、長いコード、表の表示を確認します。

CLIの動作を確認する場合は、サイトのクイックスタートに従ってexampleを起動し、タップ数と入力欄の変化を実画面で確かめてください。WebサイトのブラウザテストはFlutter操作そのものの検証を代替しません。
