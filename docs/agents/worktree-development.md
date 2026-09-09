# git gtr による並列開発

コード・文書・設定の変更を並列で進めるときは、タスクごとに git gtr の専用 worktree を使う。主 worktree は worktree の管理と統合に使い、タスクの変更を混在させない。

## 着手

1. 現在の worktree を確認する。

   ```bash
   git gtr list --porcelain
   git rev-parse --show-toplevel
   git gtr go 1
   ```

2. 現在地が既にそのタスク専用の worktree なら、そのまま作業する。現在地が `git gtr go 1` の返す主 worktree、または別タスクの worktree なら、主 worktreeから `feature/<task-slug>` を作る。

   ```bash
   git gtr new feature/<task-slug> --porcelain
   ```

   `.gtrconfig` により `develop` が基点、`origin` が remote になる。既存ブランチなど別の基点が必要な場合だけ `--from <ref>` を明示する。

3. 終了コードが 0 であることを確認し、stdout のタブ区切りレコードから `path`、`branch`、`hook_status` を読む。作成後の全操作は、絶対パスで返された `path` の配下だけで行う。人間向けログから作成成功を推測しない。

   ```text
   path	/absolute/path/to/marionette_agent-worktrees/feature-task-slug
   branch	feature/<task-slug>
   hook_status	ran
   ```

   `--porcelain` は `--yes` を含み、`--editor` および `--ai` とは併用できない。失敗時は成功レコードが出力されない。

## セットアップ結果

`.gtrconfig` の `postCreate` は、次の依存を各 worktree で生成する。

- `packages/marionette_agent`: `dart pub get`
- `example`: `flutter pub get`

`hook_status` は次のように扱う。

- `ran`: 両方の hook が完了している。
- `none` または `disabled`: hook は実行されていない。必要な依存取得を明示的に実行する。
- `skipped-untrusted` または `partial`: Agent は `git gtr trust` を実行せず、人間に状態を報告する。作業に必要なら、上記の既知の依存取得コマンドだけを対象 worktree で明示的に実行する。

hook の失敗を含む非 0 終了は作成失敗として扱う。別ディレクトリで作業を続けず、原因と残った worktree の有無を確認する。

## 並列作業と引き継ぎ

- 1つのブランチと worktree を1つのタスクだけに割り当てる。同じブランチを複数 worktree に配置する `--force` は使わない。
- コマンドは対象 worktree を作業ディレクトリとして実行する。主 worktree や別タスクの未コミット変更には触れない。
- 引き継ぎ前に対象 worktree で `git status --short --branch` を実行し、ブランチ、変更ファイル、検証コマンドと結果、`hook_status` の注意事項を報告する。

## 終了と削除

作業完了だけを理由に worktree を削除しない。利用者が明示的に後片付けを依頼した場合に限り、対象と未コミット変更を確認して `git gtr rm <branch>` を実行する。

`git gtr rm --force`、`--delete-branch`、`git gtr clean` は、削除範囲について利用者の明示的な許可がある場合だけ使う。

## 参照

- [リポジトリの `.gtrconfig`](../../.gtrconfig)
- [git-worktree-runner](https://github.com/coderabbitai/git-worktree-runner)
- [AI Agent Usage](https://github.com/coderabbitai/git-worktree-runner/blob/main/docs/agent-usage.md)
