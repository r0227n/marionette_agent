# Issue別PRワークフローの実地検証

2026-09-11に、利用者が指定した[Issue #2](https://github.com/r0227n/marionette_agent/issues/2)・[Issue #3](https://github.com/r0227n/marionette_agent/issues/3)で、実装からエビデンス付きDraft PRまで実行した。人間による確認は未実施。

## 実行条件

- 基点は両方とも `origin/develop` の `f76ebc786b556be4e64674477521d0b1f2c2351c`。Issueはopen、native依存は0件、同じIssueの既存PRなし。
- `git gtr new ... --porcelain` でIssueごとにbranchとworktreeを作成し、両方の `hook_status: ran` と依存取得成功を確認した。
- 新規の [issues-to-pr](../../.agents/skills/issues-to-pr/SKILL.md)・[simulator-verify](../../.agents/skills/simulator-verify/SKILL.md) と、管理対象外の [pr-create](../../.agents/skills/pr-create/SKILL.md) をworkerへ絶対pathで渡した。workflow文書は主checkout、製品実装は各Issueのworktreeで変更した。
- 独立したCLI workerを通常のsandbox・自動承認で並行実行した。担当は#2がAstra、#3がSol。別Issueのbranchのmerge／cherry-pickは行っていない。
- 別々のiOS 26.2 Simulator、専用runtime、session、出力先を使用した。Flutter 3.47.2、Dart 3.13.2、Marionette binding 0.6.0。
- Issueに紐づかないworkflow整備は、主checkoutの `feature/issue-workflow-skills` で実施した。

## 結果

| Issue | Branch / worktree名 | Draft PR | 自動検証 | 添付 |
| --- | --- | --- | --- | --- |
| #2 共通安全オプション | `feature/issue-2-safety-options` / `feature-issue-2-safety-options` | [#22](https://github.com/r0227n/marionette_agent/pull/22) | format・analyze・全152テスト成功 | PNG 3枚 |
| #3 単独wait | `feature/issue-3-standalone-wait` / `feature-issue-3-standalone-wait` | [#21](https://github.com/r0227n/marionette_agent/pull/21) | format・analyze・全146テスト成功 | PNG 2枚・動画1本 |

#2はiPhone Air（`C66CFC02-289C-4106-8F63-93DF694BB2C4`）で29 CLI呼出しと1集約結果を確認した。境界nonceの変化、text／JSONの項目単位の省略、省略refとidle設定不一致の操作拒否、実際のtap・日本語/絵文字入力、12.99秒の処理継続、11秒idle後の切断、明示再接続後の画面保持を確認した。

#3はiPhone 17（`DEDBBEE8-F70D-4CF2-A150-930585F683B0`）でControls→About→Controlsを操作し、要素のexists／goneをtext・JSON両形式で確認した。CLI応答と後続snapshot・画面を照合し、動画frameも確認した。

詳細なコマンド・期待結果・実測・人間の再現手順は各PRの検証記録を参照する。

- #2: 検証したコードは `857464d169bcf4d5a8eb34740b184d7c4b04e016`。記録のみを追加したheadは `63cc7a05296cc28dd3ce515ccd67371e8398658d`。検証結果と添付は[PR #22](https://github.com/r0227n/marionette_agent/pull/22)を参照。
- #3: 検証したコードは `69a57e543dba93c51ed5591bda0a04ed1df51fa8`。記録と再現手順のみを追加・修正したheadは `e9747153e44dea8e81ba36e03265a36672c5ec6c`。検証結果と添付は[PR #21](https://github.com/r0227n/marionette_agent/pull/21)を参照。

`gh pr view` と全stateのPR一覧を読み返し、それぞれが重複のない1本のopen Draft PRで、baseがdevelop、headが上記commit、テンプレート3項目と添付3件が存在し、人間確認が未チェックであることを確認した。両worktreeはclean。所有するsession・daemon・runner・アプリを終了し、割当端末だけをShutdownへ戻した。worktreeは人間確認・修正用に保持した。

## 実行中に改善した手順

- #3の最初のPR作成は、動画へ画像用alt suffixを指定したためCLIで拒否された。同じhead/baseのPRが存在しないことを確認して引数を修正し、1本だけ作成した。動画は絶対pathだけを渡す規則をpr-createへ追記した。
- 人間の再現手順で、長時間動くFlutter runnerとCLI操作を別terminalに分け、私有ディレクトリのpathと環境変数を引き継ぐことを明記した。
- 独立した手順レビューで、公開途中の添付復旧、依存解放後の基点確認、worker/端末の利用記録、正常終了とworker中断時の回収を確認し、不足を新規skillへ反映した。

## 文書・skillの確認

- `skill-creator/scripts/quick_validate.py` でissues-to-pr、simulator-verify、pr-createを検証した。
- 変更文書の相対リンク・内部見出しへの参照と、AGENTS／worktree運用／PRテンプレートの整合性、`git diff --check` を確認した。
- `skills-lock.json` と管理対象37 skillの全tracked fileが基点と同一であることを確認した。外部のimplement-spec等は変更していない。

## 検証の範囲

実地で確認したのは独立した2 Issueの並行実装・別端末検証・添付付きPR公開と、上記の動画引数エラーからの再試行。重複入力、未マージ依存の待機、1台のSimulatorの共有、worker異常終了、添付の一部成功からの復旧は手順レビューで確認し、故障を注入した実地試験はしていない。

#2の1時間の実時間待機と録画中idle終了、#3のkey以外のselectorについてのSimulator確認は行っていない。該当する既定値・shutdown経路・selector契約は自動テストまたは既存契約で確認し、詳細は各PRに記載した。必須Simulatorシナリオは両Issueとも完了している。

各PRは個別に確認する。共通parserと仕様文書に変更があるため、後の統合で競合する可能性がある。人間確認・Ready化・マージ・Issueの手動closeはこの検証では実行していない。
