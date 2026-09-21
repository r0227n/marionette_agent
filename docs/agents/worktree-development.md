# ブランチとworktreeの運用

Issueに紐づくコード・文書・設定の変更には、Issueごとに git gtr の専用worktreeを使う。Issueに紐づかないタスクは現在のcheckout内の作業ブランチで進め、worktreeを新設しない。主checkoutもIssueに紐づかないタスクの作業場所として使える。

## Issueに紐づかないタスク

1. `git status --short --branch` と `git branch --show-current` で現在地と変更を確認する。すでに今回のタスク用ブランチなら継続する。
2. 作業ブランチがなければ、利用者が指定した基点、指定がなければ最新の `origin/develop` から `feature/<task-slug>` を現在のcheckoutに作る。作成前に `git fetch origin develop` で基点を取得する。

   ```bash
   git switch -c feature/<task-slug> origin/develop
   ```

3. 別タスクのブランチ・変更を今回のブランチへ混ぜない。未コミット変更を自動stash・破棄せず、切替できなければ現在の変更と理由を報告する。同じcheckoutを複数Agentが同時に切り替えない。Issueに紐づかない複数タスクでcheckoutを共有するときは作業を直列化する。

以下のworktree作成・hook確認はIssueに紐づくタスクだけに適用する。

## Issueに紐づくタスクの着手

1. 現在の worktree を確認する。

   ```bash
   git gtr list --porcelain
   git rev-parse --show-toplevel
   git gtr go 1
   ```

2. 現在地が既にそのIssue専用のworktreeなら継続する。別の場所にそのIssueのworktreeがあれば再利用する。新規の場合だけ、主worktreeから `feature/issue-<number>-<slug>` を作る。Issue番号とbranch・pathの対応を記録し、既存PRとの重複は [issues-to-pr](../../.agents/skills/issues-to-pr/SKILL.md) で確認する。

   ```bash
   git gtr new feature/issue-<number>-<slug> --porcelain
   ```

   `.gtrconfig` により `develop` が基点、`origin` が remote になる。既存ブランチなど別の基点が必要な場合だけ `--from <ref>` を明示する。

3. 終了コードが 0 であることを確認し、stdout のタブ区切りレコードから `path`、`branch`、`hook_status` を読む。作成後の全操作は、絶対パスで返された `path` の配下だけで行う。人間向けログから作成成功を推測しない。

   ```text
   path	/absolute/path/to/marionette_agent-worktrees/feature-issue-42-example
   branch	feature/issue-42-example
   hook_status	ran
   ```

   `--porcelain` は `--yes` を含み、`--editor` および `--ai` とは併用できない。失敗時は成功レコードが出力されない。

## セットアップ結果

`.gtrconfig` の `postCreate` は、各 worktree のルートで `flutter pub get` を一度実行する。CLI・`packages/marionette_agent_util`・`example`はPub workspaceとして依存を共有し、ルートのlockfileとpackage configを生成する。

`hook_status` は次のように扱う。

- `ran`: 依存取得の hook が完了している。
- `none` または `disabled`: hook は実行されていない。必要な依存取得を明示的に実行する。
- `skipped-untrusted` または `partial`: Agent は `git gtr trust` を実行せず、人間に状態を報告する。作業に必要なら、上記の既知の依存取得コマンドだけを対象 worktree で明示的に実行する。

hook の失敗を含む非 0 終了は作成失敗として扱う。別ディレクトリで作業を続けず、原因と残った worktree の有無を確認する。

## 並列作業と引き継ぎ

- 1つのブランチと worktree を1つのIssueだけに割り当てる。同じブランチを複数 worktree に配置する `--force` は使わない。
- コマンドは対象 worktree を作業ディレクトリとして実行する。主 worktree や別タスクの未コミット変更には触れない。
- 引き継ぎ前に対象 worktree で `git status --short --branch` を実行し、ブランチ、変更ファイル、検証コマンドと結果、`hook_status` の注意事項を報告する。

CLIの検証資源の分離とSimulatorの利用調整は [simulator-verify](../../.agents/skills/simulator-verify/SKILL.md) に従う。コードを並行実装できても、共有Simulatorの操作は直列化する。

## 終了と削除

作業完了だけを理由に worktree を削除しない。利用者が明示的に後片付けを依頼した場合に限り、対象と未コミット変更を確認して `git gtr rm <branch>` を実行する。

`git gtr rm --force`、`--delete-branch`、`git gtr clean` は、削除範囲について利用者の明示的な許可がある場合だけ使う。

## 参照

- [リポジトリの `.gtrconfig`](../../.gtrconfig)
- [git-worktree-runner](https://github.com/coderabbitai/git-worktree-runner)
- [AI Agent Usage](https://github.com/coderabbitai/git-worktree-runner/blob/main/docs/agent-usage.md)
