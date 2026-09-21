# marionette_agent の開発ガイド

Marionette対応Flutterアプリを操作するDart CLIとstdio MCPサーバーを開発する。初版はmacOSからiOS Simulatorを操作する。MCPの契約は[SPEC](docs/SPEC.md#stdio-mcpサーバー)を参照する。

## 作業開始

1. コード・文書・設定を変更するタスクでは [ブランチとworktreeの運用](docs/agents/worktree-development.md) を読む。Issueに紐づくタスクはIssueごとの専用worktree、Issueに紐づかないタスクは現在のcheckout内の作業ブランチで進める。後者のためにworktreeを新設しない。
2. 機能の追加・変更では [SPEC.md](docs/SPEC.md) を読み、CLI契約と対象範囲を確認する。
3. 実装では [ARCHITECTURE.md](docs/ARCHITECTURE.md) を読み、担当モジュールと依存方向を確認する。

## IssueからPRまで

- Issue番号・URLを指定した実装〜PR作成の依頼では [issues-to-pr](.agents/skills/issues-to-pr/SKILL.md) を使う。複数入力は重複を除き、1 Issue = 1ブランチ = 1 worktree = 1 PRとする。独立したIssueを並行して進め、依存するIssueは前提がdevelopへ入るまで待つ。
- CLIの実環境検証とエビデンス取得では [simulator-verify](.agents/skills/simulator-verify/SKILL.md)、新規PR作成では [pr-create](.agents/skills/pr-create/SKILL.md) を使う。Issueの有無にかかわらず検証基準は同じ。
- 動作確認の録画に操作対象・見る場所・観測結果を示す編集では [video-evidence](.agents/skills/video-evidence/SKILL.md) を使う。
- Agentの完了地点は、必須検証とエビデンス確認を終えたDraft PRを、人間が再現できる確認手順付きで引き渡した時点。人間の動作確認は未実施として残し、Ready化・マージ・Issueの手動closeは別途依頼された場合に行う。必須検証や添付が未完了なら完了扱いにしない。

## 担当と実装規約

- コア基盤とswipeはAstra担当。その他の初版機能は別モデル担当。
- 実装対象は `packages/marionette_agent/`。隣接する `../agent-browser` と `../marionette_mcp` は参考実装として読み、変更や配布時のpath依存を前提にしない。
- 上流 `marionette_mcp/src/` のimportはbackend adapterに集約する。個別コマンドは共通のsession、対象解決、失効、エラー契約を使う。
- UI操作を自動再送しない。古いrefや曖昧な対象はSPECのエラーとして返す。
- stdoutはCLIの結果、診断はstderrに送る。認証URI・入力文字列を診断ログへ出力しない。

## 検証と引き継ぎ

コード変更後は `packages/marionette_agent` 内で `dart format`、`dart analyze`、関連する `dart test` を実行する。引き継ぎ時は全体テストも実行する。Simulator検証が必要なタスクは実環境で確認し、未実施なら理由を記録して未完了のままにする。文書のみの変更ではリンク・仕様・タスクの整合性を確認する。

文書編集・CLI入力や出力の変更では、[文書の配置・翻訳方針](docs/ja/documentation.ja.md) を読み、該当する日英のサイトページと補足を同じPRで更新する。公開言語は英語を主とし、英語の補足は`docs/`直下、日本語は`docs/ja/`へ置く。利用ガイドはwebsiteを正本として重複させない。

公開サイト・補足の変更は[websiteの検証手順](website/README.md)に従い、日英対応・リンク・サイトの全検証と表示確認を行う。

CLIの機能追加・変更時は、動作確認用アプリ [example/](example/) をiOS Simulatorで起動し、実装したCLIから接続・操作して実際の挙動を確認する。CLIの応答に加えて、操作後の画面や状態が期待どおりに変化したことを確認する。

並行検証ではIssueごとにSimulatorのUDID・CLIのruntimeディレクトリ・session・出力先を分離する。Simulatorを共有する場合は、起動から操作・録画・終了までを直列化する。

共通契約を変えるときはSPEC・ARCHITECTUREと影響タスクを同時に更新する。

## Skillの管理

Skillを追加・編集する前に [skills-lock.json](skills-lock.json) を確認する。管理対象の外部skillはディレクトリ内のファイルを変更せず、lockの削除や書換えで管理を外さない。リポジトリ固有の運用は、新規skillまたは管理対象外のskillとAGENTS.mdで定義する。

複数Issueの開発経路は `issues-to-pr` に統一する。外部の `implement-spec` 等にある単一PRへの統合・検証前のPR公開・Ready化・worktree削除は、このリポジトリのIssue別ワークフローへ取り込まない。

## 必要なときに読む文書

- GitHub Issuesの参照・更新: [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md)。外部投稿は利用者が依頼した範囲で行う。
- Issueの分類: [docs/agents/triage-labels.md](docs/agents/triage-labels.md)。
- 用語・ADRの参照: [docs/agents/domain.md](docs/agents/domain.md)。初版の用語はSPECに定義する。将来CONTEXTへ移す場合は定義を二重管理しない。
- PR作成時のbase branchは `develop`。
