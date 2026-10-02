# コンテナでのIssue開発とホスト検証

汎用の [container-issue-pr](../../.agents/skills/container-issue-pr/SKILL.md) を使い、
Issue取得・作業範囲の確定 → コンテナ内でgtr worktree作成 → ホストファイルのコピー
→ Agentによる実装 → ホストのgtr worktreeで動作確認 → Draft PR作成の順で進める。
1 Issueにつき両環境に1 worktreeずつを割り当て、同じIssue branchを対応させる。

## 本プロジェクト用イメージ

リポジトリのルートで実行する。ビルドcontextはDockerfileのディレクトリだけで、
ソースコード、ホストのGit履歴や認証情報はイメージへ含めない。

```bash
docker build -t marionette-agent-dev:flutter-3.47.2 docker/agent
bash docker/agent/verify-image.sh "$PWD"
```

[Dockerfile](../../docker/agent/Dockerfile) はホストと同じFlutter 3.47.2／Dart 3.13.2、
gtr 2.11.0、Codex CLI 0.154.0とLinuxの開発ツールを導入する。
Flutterのrevisionも照合する。AgentはUID 10001で実行し、SDKとpub cacheへ書き込める。
`FLUTTER_VERSION`・`FLUTTER_REVISION`・`GTR_VERSION`・`CODEX_VERSION`はbuild argsで変更できる。

検証スクリプトは実際にコンテナ内でgtr worktreeを作成してからホストの
`packages/`・`example/`をコピーし、ツール起動、依存取得、解析、移植可能なCLI契約テスト、
utilテスト、exampleのwidgetテストを実行する。停止したコンテナとログの場所を返す。
modelへの認証・推論リクエストは送らない。

Linux側のテストは開発環境の確認であり、macOS側の必須検証を置き換えない。
既存の全体テストにはmacOS版`stat -f`や一時ディレクトリ権限の前提があるため、
CLIの全体テストはホストで実行する。iOS SimulatorとXcodeもホスト側で利用する。

## 設定して実行する

[workflow.example.json](../../docker/agent/workflow.example.json) をリポジトリ外へコピーし、
`source`・`state_root`・共有の`lock_root`を実在する絶対パスへ変更する。
コピー元はcleanかつ取得した`origin/develop`と同じHEADにする。
除外ルールと追加コピー対象は`copy`、並列数は`parallelism`で変更できる。

Agentの起動引数は、依頼に合わせてコンテナ内のYOLOモードに設定している。

```json
["codex", "exec", "--dangerously-bypass-approvals-and-sandbox", "-"]
```

これは`docker exec`でのみ実行される。ホスト側の検証・GitHub操作はホストの権限設定に従う。
別Agentを使う場合は、そのCLIを導入したイメージと`agent.argv`を指定する。
非対話で必要な認証はホストに用意したenvファイルを`container.env_file`で明示的に指定する。
CodexのAPIキー認証なら`CODEX_API_KEY`を使用できる。実際のキーを設定例やPRへ書かない。
既存のログイン情報を自動探索・転送する処理はない。

各Issueの受入条件に合うホスト側の検証スクリプトを用意し、設定例末尾の
`/absolute/path/to/reviewed-issue-acceptance.sh`を置き換える。
この項目を残したままなら検証は失敗し、PR公開へ進まない。
起動・接続・操作・期待状態の確認・スクリーンショット／録画・終了をそのスクリプト内で行う。
共有Simulatorには同じresource名とlockディレクトリを使い、runtime・session・出力先はIssue別にする。
`CIP_RUN_DIR`と`CIP_WORKTREE`をスクリプトから参照できる。

```bash
bash .agents/skills/container-issue-pr/scripts/workflow.sh prepare /absolute/config.json 42
# 表示されたrunのissue.json/comments.jsonを読み、受入条件を整理してtask.mdを書く。
bash .agents/skills/container-issue-pr/scripts/workflow.sh work /absolute/run
bash .agents/skills/container-issue-pr/scripts/workflow.sh collect /absolute/run
# 表示されたホストworktreeで差分をレビューする。
bash .agents/skills/container-issue-pr/scripts/workflow.sh verify /absolute/run
bash .agents/skills/container-issue-pr/scripts/workflow.sh publish /absolute/run \
  '変更内容に合うPRタイトル' /absolute/completed-pr-body.md /absolute/evidence.png
```

PR本文は本リポジトリのテンプレートを使い、Agentの実際の確認結果と人間の再現手順を分ける。
人間による確認は未実施としてDraftで渡す。添付を含む公開の復旧と後片付けはSkillの手順に従う。
gtrの自動copy/hooksは両環境で無効にし、既知の依存取得をホストの検証コマンド内で実行する。
gtrのtrust変更、worktreeの自動削除、Ready化・merge・Issue closeは行わない。

## 補助ツールの結合テスト

```bash
bash .agents/skills/container-issue-pr/tests/integration.sh marionette-agent-dev:flutter-3.47.2
```

Docker・Git・gtr・rsyncとホストのチェックは実物を使う。GitHubとAgentの応答はfixtureにし、
テスト用のローカルbareリポジトリへpushする。外部Issue/PRやmodel呼び出しは発生しない。
コピー除外・追加ファイル・バイナリ・実行ビット・symlink・削除・並列失敗分離・
ホストworktree保護・検証ロック・検証後の変更検出・Draft PR契約を確認する。

参照: [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)、
[非対話実行](https://learn.chatgpt.com/docs/non-interactive-mode)、
[Flutter SDK](https://docs.flutter.dev/install/archive)。
