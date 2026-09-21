# Issue worker

統括Agentから1件のIssueと専用worktreeを受け取ったworkerが読む。割当Issueについて実装・検証・Draft PR作成まで担当する。

1. cwdの絶対pathとbranchが割当と一致することを確認し、そのworktreeの `AGENTS.md`、Issue本文・コメント、`docs/SPEC.md`、`docs/ARCHITECTURE.md` を読む。別Issueの実装や主checkoutの変更は担当外とする。
2. 受入条件それぞれに実装箇所と確認方法を対応付けて実装する。CLIの入力・結果が変われば日本語CLIリファレンスとhelpも更新する。共通契約の変更は関連仕様にも反映する。仕様の不足はコード・既存契約から補い、実装を左右する不明点だけ統括Agentへ返す。
3. AGENTS.mdのformat・analyze・関連テスト・引き継ぎ前の全体テストを実行する。exampleや他パッケージに変更があればその領域の検証も実施する。失敗は修正し、受入条件とdiffを照合して取りこぼしを確認する。
4. [simulator-verify](../../simulator-verify/SKILL.md) で必要な実環境検証と画像・動画を自分で取得する。Simulatorの割当待ちは統括Agentへ報告し、他workerの端末を流用しない。文書のみ等の対象外判断は [pr-create](../../pr-create/SKILL.md) に従う。
5. 検証記録はPR本文と画像・動画の添付へ残す。作業中のログとエビデンスはタスク専用の一時出力先へ保存し、Issueが保存先を明示した場合はその指定に従う。過去文書のリンクだけを理由に廃止済みの記録ディレクトリを再作成しない。実行コマンド・期待/実際の結果・検証対象commit・環境・画像/動画の対応・人間の再現手順を記録する。URIや機密情報を残さない。
6. [pr-create](../../pr-create/SKILL.md) で対象Issue1件を関連付け、検証・添付が揃ったDraft PRを作成する。検証後にコードを修正したら影響する検証とエビデンスを取り直す。人間確認欄は未チェックのままにする。
7. 統括AgentへIssue URL、branch、絶対worktree path、最終commit、PR URL、検証コマンドと結果、検証記録、添付済みエビデンス、人間の確認手順、制約を返す。PRが作れなかった場合も現在の変更と阻害理由を返し、完了とは報告しない。
