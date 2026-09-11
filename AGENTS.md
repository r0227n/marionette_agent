# marionette_agent の開発ガイド

Marionette対応Flutterアプリを操作するDart CLIを開発する。初版はmacOSからiOS Simulatorを操作する。MCP対応は今回の対象外。

## 作業開始

1. コード・文書・設定を変更するタスクでは [git gtr による並列開発](docs/agents/worktree-development.md) を読み、タスク専用worktreeを選択または作成する。
2. 機能の追加・変更では [SPEC.md](docs/SPEC.md) を読み、CLI契約と対象範囲を確認する。
3. 実装では [ARCHITECTURE.md](docs/ARCHITECTURE.md) を読み、担当モジュールと依存方向を確認する。

## 担当と実装規約

- コア基盤とswipeはAstra担当。その他の初版機能は別モデル担当。
- 実装対象は `packages/marionette_agent/`。隣接する `../agent-browser` と `../marionette_mcp` は参考実装として読み、変更や配布時のpath依存を前提にしない。
- 上流 `marionette_mcp/src/` のimportはbackend adapterに集約する。個別コマンドは共通のsession、対象解決、失効、エラー契約を使う。
- UI操作を自動再送しない。古いrefや曖昧な対象はSPECのエラーとして返す。
- stdoutはCLIの結果、診断はstderrに送る。認証URI・入力文字列を診断ログへ出力しない。

## 検証と引き継ぎ

コード変更後は `packages/marionette_agent` 内で `dart format`、`dart analyze`、関連する `dart test` を実行する。引き継ぎ時は全体テストも実行する。Simulator検証が必要なタスクは実環境で確認し、未実施なら理由を記録して未完了のままにする。文書のみの変更ではリンク・仕様・タスクの整合性を確認する。

`packages/marionette_agent/` の実装変更によってCLIの入力または出力結果が変わる場合は、[docs/ja/cli-reference.ja.md](docs/ja/cli-reference.ja.md) も同時に更新する。

CLIの機能追加・変更時は、動作確認用アプリ [example/](example/) をiOS Simulatorで起動し、実装したCLIから接続・操作して実際の挙動を確認する。CLIの応答に加えて、操作後の画面や状態が期待どおりに変化したことを確認する。

共通契約を変えるときはSPEC・ARCHITECTUREと影響タスクを同時に更新する。

## 必要なときに読む文書

- Issueをコンテナのgtr worktreeで実装し、ホストのworktreeで検証してPRを作成する場合: [コンテナ開発](docs/agents/container-development.md)。汎用Skill・本プロジェクト用イメージ・YOLO起動設定と検証手順を参照する。
- GitHub Issuesの参照・更新: [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md)。外部投稿は利用者が依頼した範囲で行う。
- Issueの分類: [docs/agents/triage-labels.md](docs/agents/triage-labels.md)。
- 用語・ADRの参照: [docs/agents/domain.md](docs/agents/domain.md)。初版の用語はSPECに定義する。将来CONTEXTへ移す場合は定義を二重管理しない。
- PR作成時のbase branchは `develop`。
