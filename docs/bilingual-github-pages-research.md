# marionette-agentの日英ドキュメントサイト構成案

調査日: 2026-09-21。状態: **採用前の比較記録。以下の現状・提案は調査時点のもの。**

> 後続の依頼でStarlightを採用し、本文は既存文書の移行ではなくゼロベースで執筆する方針になった。以下は採用前の比較記録であり、現在の実装・執筆・公開手順は[website/README.md](../website/README.md)を参照する。

調査対象はmarionette_agentの`6364bd84db3ac55a1cd7a8ef4256f13f1260e604`と、隣接agent-browserの`72007a6788d863611b23bed0b59d0d659c638d8e`。公式ドキュメントとローカルソースを確認した。subagent起動ツールは利用できないため、このタスク内で独立した資料の読取りを並行した。

## 推奨

**同一リポジトリの`website/`にAstro + Starlightを置き、日英のMarkdownから静的サイトを生成してGitHub Actions経由でGitHub Pagesへ公開する。**

agent-browserの導入→クイックスタート→リファレンスという導線と、簡潔なサイドバーを参考にする。本文・言語切替・検索・目次はStarlightの標準機能を使い、独自実装は配色、ロゴ、トップページのデモ程度から始める。本文はMarkdownを基本とし、コンポーネントが必要なページだけMDXにする。[Starlightのページ構成](https://starlight.astro.build/guides/pages/)

## 現状から分かったこと

| 対象 | 確認した事実 | 設計への影響 |
| --- | --- | --- |
| agent-browser | [package.json](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/docs/package.json)はNext.js・React・MDXを使用。[next.config.mjs](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/docs/next.config.mjs)に静的export設定なし | 見せ方を参考にし、フレームワークの移植を前提にしない |
| agent-browserの実行時処理 | [検索API](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/docs/src/app/api/search/route.ts)がリクエストの検索語を処理し、[チャットAPI](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/docs/src/app/api/docs-chat/route.ts)がモデルを呼ぶ。[layout](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/docs/src/app/layout.tsx)もcookieを読む | 現行実装をそのままPagesへ置く構成にはできない |
| 既存原稿 | [日本語入口](ja/README.md)、[CLIリファレンス](ja/cli-reference.ja.md)など、`docs/ja/`は6ファイル・2,094行。ルートREADMEはない | 既存原稿の整理・英訳を中心にする。ルートREADMEに言語別の入口を作る |
| 原稿の対象読者 | [command-contract](ja/command-contract.ja.md)はコマンド追加時の実装契約 | 利用者向けサイトと開発者向け内部文書を区別する |
| 配布状態の記述 | [pubspec.yaml](../pubspec.yaml)は`0.0.1`・`publish_to: none`、[CHANGELOG](../CHANGELOG.md)先頭は`1.0.0` | 公開前に版表記を整える。pub.devから導入できるとは案内しない |
| 公開ワークフロー | 調査対象の`.github/workflows/`にあるのはラベル同期のみ | docs検証・Pagesデプロイを追加する必要がある。GitHub側のPages設定は未確認 |

Next.jsでも静的exportは可能だが、cookieやリクエスト依存のRoute Handlerなどは対象外。agent-browserと同等のAIチャットを提供するならPagesとは別のバックエンド設計が必要になる。今回の文書公開ではPagefindによる静的検索を採用する。[Next.jsの静的export制約](https://nextjs.org/docs/app/guides/static-exports#unsupported-features)

## 候補の判断

| 候補 | 今回の評価 | 選ぶ条件 |
| --- | --- | --- |
| **Astro + Starlight** | 第一候補。日英対応・静的検索・Markdown本文と独自ページの組合せが目的に合う | 紹介と技術文書を同じサイトで継続更新する |
| VitePress | 有力な代替。localesとMiniSearchによるローカル検索を設定できる | Vueへの習熟や、文書中心の標準テーマを優先する |
| Docusaurus | 多言語とドキュメントのバージョン管理を備える | 互換性の異なる複数の安定版を継続サポートする要件がある |
| Next.js + MDXによる独自構築 | 実現可能だが、参考実装の静的化と日英対応の追加が必要 | React基盤の共有や、独自UIの要件が採用コストを上回る |

判断根拠: [Starlight i18n](https://starlight.astro.build/guides/i18n/)、[Starlight検索](https://starlight.astro.build/guides/site-search/)、[VitePress i18n](https://vitepress.dev/guide/i18n)、[VitePress検索](https://vitepress.dev/reference/default-theme-search)、[Docusaurus i18n](https://docusaurus.io/docs/i18n/introduction)、[Docusaurusバージョン管理](https://docusaurus.io/docs/versioning)。これは要件と保守範囲からの評価で、各ツールの性能比較実験ではない。

Starlightの公式導入ページは調査時点でもbetaと記載している。採用時は互換性を確認したAstro/Starlight/Nodeの組合せとlockfileを固定し、依存更新PRでビルド・検索・言語切替を確認する。[更新に関する公式説明](https://starlight.astro.build/getting-started/#updating-starlight)

## ファイルとURL

推奨する移行後の配置:

```text
README.md                         # 概要と日英サイトへの入口
docs/
  SPEC.md                         # 製品契約
  ARCHITECTURE.md                  # 内部設計
  agents/                         # 開発運用
  ja/                             # 移行済み文書は移転案内にする
website/
  package.json
  package-lock.json
  astro.config.mjs
  src/
    content.config.ts
    content/docs/
      ja/
        index.md
        getting-started/installation.md
        getting-started/quick-start.md
        guides/...
        reference/...
      en/                         # jaと同じ相対パス
        index.md
        getting-started/installation.md
        getting-started/quick-start.md
        guides/...
        reference/...
    assets/                       # 画像と短いデモ素材
    styles/custom.css
  scripts/                        # 必要最小限の文書整合チェック
.github/workflows/
  docs-check.yml
  docs-deploy.yml
```

標準のプロジェクトPagesを使う場合の**想定URL**は次のとおり。公開済みURLではない。

```text
https://r0227n.github.io/marionette_agent/ja/getting-started/quick-start/
https://r0227n.github.io/marionette_agent/en/getting-started/quick-start/
```

英数字の同じslugを両言語で使用する。`/ja/`内のファイルに`.ja.md`を重ねない。言語切替では対応する同じページへ移動し、翻訳で変わる見出しアンカーは無理に引き継がない。共有する必要があるアンカーだけ固定IDを定める。

設定の概略（サイト全体の完成コードではない）:

```js
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://r0227n.github.io',
  base: '/marionette_agent',
  output: 'static',
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'marionette-agent',
      defaultLocale: 'ja',
      locales: {
        ja: { label: '日本語', lang: 'ja' },
        en: { label: 'English', lang: 'en' },
      },
    }),
  ],
});
```

日本語の既存原稿が充実しているため、初期案では`defaultLocale: 'ja'`とする。これはfallbackの基準であり、英語を後回しにする方針ではない。初回公開対象の利用者向けページは全て日英を揃える。サイト入口は日本語を既定とし、Englishへの切替を明示する。将来既定言語を変えても`/ja/`・`/en/`のURLは保つ。[Starlightのlocale設定](https://starlight.astro.build/guides/i18n/)

`base`の設定だけで任意の手書きURLが自動修正されるとは考えない。独自リンク・画像・ダウンロード・検索assetもサブパス込みで確認する。ソース内の`.md`リンクと公開ページへのリンクは別に検査する。[AstroのPages設定](https://docs.astro.build/en/guides/deploy/github/)

## 情報設計と既存原稿の移行

最初のホームには「何ができるか」「対応ホストと対象」「導入へのリンク」「snapshot→操作→再観測の短いデモ」を置く。各コマンドの説明は、構文、具体例、結果、前提、失敗時の対処の順に揃える。

| ナビゲーション | 内容 | 主な移行元 |
| --- | --- | --- |
| はじめに / Getting started | 概要、インストール、exampleで最初の操作、自分のFlutterアプリへの組込み | [README](ja/README.md)、[example](../example/README.md) |
| 基本概念 / Concepts | session、snapshot、refの寿命、selector、JSON出力 | [SPEC](ja/SPEC.ja.md)、[CLIリファレンス](ja/cli-reference.ja.md) |
| ガイド / Guides | MCP、同梱Skills、workflow、スクリーンショット・録画、headless | [README](ja/README.md)、[headless](ja/headless.ja.md)、[workflow仕様](ja/workflow-file-spec.ja.md) |
| リファレンス / Reference | コマンド群、共通オプション、環境変数・設定、エラー、workflow schema、MCP tools | [CLIリファレンス](ja/cli-reference.ja.md)、[追加コマンド](ja/cli-parity.ja.md)、[SPEC](ja/SPEC.ja.md) |
| トラブルシューティング / Troubleshooting | doctor、接続失敗、STALE_REF、provider不足、プラットフォームの制約 | 既存利用ガイドと実装契約 |

777行のCLIリファレンスを1ページに収め続けず、接続・観測・操作・録画などのコマンド群へ分割する。追加コマンドも通常の索引へ統合し、必要なproviderと制約を各ページに明示する。初版のmacOSホスト対応と、起動・録画対象の複数プラットフォームを混同しない。[現行の対象範囲](ja/SPEC.ja.md)

`SPEC.md`・`ARCHITECTURE.md`・`docs/agents/`・検証記録は引き続き開発者向けの管理文書とする。`command-contract.ja.md`も初期の利用者向けナビゲーションには入れない。実装契約を翻訳した大きなサイトを先に作るより、導入から使用・復旧までを両言語で完結させる。

移行は原稿単位で行う。移した本文の編集元を`website/src/content/docs/`に一本化し、旧パスは対応ページへの短い案内に置き換える。旧文書への内部リンク・主要アンカー・CLI help中のパスも対応表で洗い出す。旧パスを即削除したり、同じ日本語本文を両方で手編集したりしない。

現行[AGENTS.md](../AGENTS.md)はCLI入出力変更時の`docs/ja/cli-reference.ja.md`更新を要求する。**移行する実装PRで、移行対象の参照と文書更新ルールを新しい正本へ同時に変更する必要がある。** 本調査ではルールも既存本文も変更していない。

## 日英を維持する運用

1. 公開対象のページ集合を両言語で一致させる。ディレクトリ相対パスをページIDとして使い、初期段階で別のID管理基盤は作らない。
2. CLIの利用方法・結果・制約が変わるPRでは、対応する日英本文を同じPRで更新する。日本語の校正だけなら翻訳影響なしと理由を記録できるようにする。
3. `session`、`snapshot`、`ref`などの用語・訳語を小さな対訳表で揃える。コマンド、フラグ、JSON key、error codeは翻訳しない。コードコメントや説明文は訳す。
4. コード例、JSON/YAMLサンプル、機械的な既定値は同じ入力元を使う。既存の[workflow例](../samples/workflows/README.md)を活用する。
5. CIでページ欠落、内部リンク、設定・生成データの不整合を検出する。両方のファイルが変更されたことだけでは訳の正確さを保証できないため、意味・数値・否定条件はレビューする。
6. AI翻訳を使う場合は下訳としてPRへ含める。英語でも手順が通り、条件・禁止事項・結果が同じ意味であることを確認する。

Starlightには未翻訳ページを既定言語で表示して通知する機能があるが、日英対応を公開条件とする今回の主要ページでは、欠落をCIで止める方針が合う。将来、補足記事だけ例外を設ける場合には、翻訳済みページと区別して表示する。[fallbackの公式仕様](https://starlight.astro.build/guides/i18n/#fallback-content)

検索はStarlight標準のPagefindを使う。PagefindはHTMLの`lang`によって索引を分ける。日本語の分かち書きはextended版で対応するため、採用した依存構成のproduction buildで日本語検索を実測する。「接続」「録画」「要素参照」「snapshot」「STALE_REF」を代表語にする。言語切替後に適切な言語の結果が出ることも確認する。[Starlight検索](https://starlight.astro.build/guides/site-search/)、[Pagefind多言語対応](https://pagefind.app/docs/multilingual/)

## リファレンスと生成範囲

現状の[CliCommand](../lib/src/cli/command.dart)は`ArgParser`と`decode`を持ち、[help](../lib/src/cli/help.dart)には手書き構文説明もある。全ての位置引数・前提・副作用・復旧手順を一つの構造化データから取得できる設計ではない。**CLIリファレンスをすぐ完全自動生成できるとは見積もらない。**

初期公開は既存ガイドを整理し、コマンド索引と現行parserの一覧を照合するところから始める。次段階で、共通オプションや列挙値など確実に取り出せる項目の生成を検討する。利用例・意味・制約は執筆し、実装から抽出できない意味を生成処理で推測しない。

MCP tool schemaの入力元は[mcp/catalog.dart](../lib/src/mcp/catalog.dart)、workflow schemaの入力元は[workflow/schema_catalog.dart](../lib/src/workflow/schema_catalog.dart)。これらの機械的な構造を別の手書きJSONで再定義しない。生成物はサイトビルドに入力し、Dartの契約コードがサイト側へ依存する構成にはしない。

この製品の主な利用面はCLIとstdio MCPなので、初期サイトはコマンド・設定・ツールの説明を優先する。Dart APIドキュメントやpub.devへの導線は、公開ライブラリ・配布方針が整った段階で追加する。

Agent向けには、次段階で本文と同じ原稿からMarkdownダウンロードと`llms.txt`のリンク集を生成する案がある。人向け本文と別の要約本文を手編集しない。効果は保証せず、通常のHTML・ナビゲーション・検索の品質を先に確保する。

## GitHub Actionsと公開する版

PRのbaseは既存運用どおり`develop`。PR先と公開対象の版は分けて決める。

| 時期 | 公開元の提案 | サイト上の表示 |
| --- | --- | --- |
| 初期・開発版を案内する間 | `develop`へマージされた、検証済みの同一commit | 「開発版」、package version、対象commit |
| 安定版リリース開始後 | 公開済みrelease tagが指すcommit | 対応するrelease version |
| 安定版の文書だけを訂正 | そのreleaseを基点とした文書訂正用のrefを検証して手動公開 | 対応releaseと文書revision |

初期にdevelopを公開するなら、ソースからの導入手順も表示したcommitに合わせる。安定版へ切り替えた後はdevelopの自動公開を止め、未リリース機能が安定版の説明へ混ざらないようにする。複数世代の同時サポートが必要になったときに初めてversioned docsを評価する。[Docusaurusもversioningの複雑性を説明している](https://docusaurus.io/docs/versioning)

推奨フロー:

```text
PR → npm ci → 文書整合チェック → 型・静的ビルド → リンク・ブラウザ確認
公開対象のcommit → 同じ検証 → Pages artifact → deploy-pages
```

- PagesのSourceをGitHub Actionsにする。ビルド生成物`website/dist/`を公開し、生成HTMLをソースブランチへcommitしない。
- `docs-check.yml`はPRで実行する。サイト原稿だけでなく、抽出対象のCLI/MCP/schemaやバージョン情報が変わった場合も検証対象にする。
- `docs-deploy.yml`は公開対象のイベントからだけ実行する。PRから本番を上書きしない。
- buildは`contents: read`、deploy jobには`pages: write`と`id-token: write`を与え、`github-pages` environmentと`needs`で検証済みartifactへ接続する。
- deployのconcurrencyを設定し、異なる日英版を別々に公開せず、1 artifactで公開する。workflow内の外部Actionsも検証済みの版へ固定する。
- 初期の文書移行ではNodeのみでサイトを構築する。Dart由来の参照生成を追加するときは、必要なSDK・生成手順を別途明示する。

設定根拠: [GitHub Pagesのcustom workflow](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)、[AstroのPagesデプロイ](https://docs.astro.build/en/guides/deploy/github/)。GitHubのリポジトリ権限・Pages設定・environmentの状態は実装時に確認する。

## 実装の段階と受入条件

1. **公開基盤を小さく検証する。** 日英のホーム・導入・クイックスタートでStarlightを構築し、実際のサブパスでbuild/previewする。この時点はサイト基盤の確認であり、全ドキュメントの移行完了とはしない。
2. **利用者向け原稿を移行・英訳する。** 上のナビゲーションに沿って文書を整理し、旧リンク対応・AGENTSの正本変更・root READMEの入口を揃える。開発用内部文書は対象を広げない。
3. **CIと公開を仕上げる。** 言語別のページ集合、内部リンク、代表検索、モバイル表示を検査し、公開版表示と対象commitを確定する。実装時の依頼範囲に従ってPages公開へ進む。
4. **運用後に必要な拡張を加える。** 機械的なリファレンス生成、Markdown配信、デモ追加、複数バージョン対応を個別に判断する。

初回公開の受入条件:

- 公開対象の利用者向けページに日英両方の本文があり、同じコマンド・既定値・制約を説明している。
- `/marionette_agent/ja/`と`/marionette_agent/en/`の深いURLを直接開ける。再読込、404、画像、コードコピー、検索がサブパス上で機能する。
- 言語切替は対応ページへ移動する。タイトル、description、ナビゲーション、`html lang`、canonical、hreflang、sitemapを生成HTMLで検査する。両言語のcanonicalを片方に集約しない。
- production buildの検索で、日本語本文・英語本文・コマンド名・エラーコードから目的のページへ到達できる。
- スマートフォン幅・キーボード操作・コードブロックの横スクロールで本文とナビゲーションを使える。
- 導入手順の対応版と配布方法が正しい。新設・変更したCLI例はexampleアプリで既存のSimulator検証方針に沿って確認する。
- 本文移行に伴う旧リンク・主要アンカーへの案内を確認し、同じ本文の手編集箇所を二重に残さない。

本調査で実施したのは資料確認と提案文書の整合チェックのみ。Astroプロジェクトの作成、候補サイトの実測、翻訳、CLI変更、Simulator検証、PR作成、デプロイは行っていない。
