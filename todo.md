# Issue #13 進捗

担当: gpt-6-astra / xhigh（Issue #13専任worker）。着手時のAGENTS.mdにtodo.mdの指定はなく、既存todo.mdもなかったため、本ファイルを入口として整備した。詳細な受入対応・検証結果・再現手順はPR本文と添付に残す。

- [x] 共通オプションへPNG/JPEG形式とJPEG品質を追加
- [x] 白背景合成・拡張子・自動名・複数画像・元の期限・排他的保存を実装
- [x] SPEC・ARCHITECTURE・日本語CLIリファレンス・help更新
- [x] format / analyze / 関連test（concurrency=1）
- [x] 全test（concurrency=1、179件成功）
- [x] 専用Simulatorで製品CLIのtext/JSONと実画面を確認し、全選択画像を開く
- [x] 所有session・daemon・runner・appの終了、専用SimulatorのShutdown、資源解放確認
- 公開・再読結果はGitHubのdevelop宛Draft PRと`/private/tmp/mra-p2-20260912/worker-13-result.md`へ記録する。
- [ ] 人間による動作確認

状態: Agent検証完了、人間確認待ち。2026-09-13、実装commit `3bf0d26c2bd10435e4f4a69514837d17bbe0a7ee`の全体179 tests、53回の製品CLI呼出し、全14画像の確認、専用資源の終了とShutdownを確認済み。Draft PRで引き渡し、人間確認は未実施として残す。

統合注意: Issue #12もscreenshot周辺を変更する。共通オプション・parser・runner・artifact writer・画像テスト・同じ仕様書が競合候補。このbranchは指定develop基点からIssue #13だけを実装し、他Issueのmerge/cherry-pick/stackは行っていない。
# Issue #8 進捗

- 担当: Astra（割当: gpt-6-astra / xhigh、単独worker）
- Branch: `feature/issue-8-environment-defaults`
- Base: `50ccf97f47ecf03a51ea3c5646c9164325570c0b` (`origin/develop`)
- 着手時に既存todo.md／Issue #8記録がないことを確認し、本記録を整備。
- [x] 共通オプションの環境fallback、help、SPEC、ARCHITECTURE、日本語CLIリファレンス
- [x] 環境を隔離したparser／CLIテストを追加
- [x] format、analyze、関連21件、全170件（concurrency=1）、追加assertion後の環境7件
- [x] 割当Simulatorで製品CLI 24呼出し・text/JSON・画像3枚を確認し終了処理
- [x] Draft PR用の検証記録、画像添付候補、人間の再現手順を準備
- [ ] 人間による確認

検証コマンド、期待／実際の結果、対象commit、エビデンスはPR本文と添付に残す。

公開・添付確認の最終結果はworker返却先 `/private/tmp/mra-p2-20260912/worker-8-result.md` に記録する。

統合時の注意: #12・#13とは独立したdevelop基点で実装する。screenshot本体は変更しない。共通parser/helpとSPEC・ARCHITECTURE・日本語CLIリファレンスに統合時の競合候補がある。他Issueの実装を取り込まない。

# Issue #11 progress

Owner: sole Issue #11 worker (gpt-6-astra, medium).
Branch: `feature/issue-11-annotated-screenshot`.

No todo.md existed when implementation started; this file records the issue's
requested progress location. Detailed commands, expected/actual results,
environment, verified commits and human reproduction steps are recorded in
[PR #32](https://github.com/r0227n/marionette_agent/pull/32).

- [x] Investigate fixed 0.6.0 screenshot and logical bounds source.
- [x] Implement opt-in mapped capture, annotation and explicit unsupported errors.
- [x] Update SPEC, ARCHITECTURE, Japanese CLI reference and help.
- [x] Final format, analyze and serial full tests (176 passed); example tests (5 passed).
- [x] Verify assigned Simulator images, refs, stale errors and unsupported provider (39 CLI calls; 9 inspected images).
- [x] Teardown owned resources and publish inspected evidence-backed [Draft PR #32](https://github.com/r0227n/marionette_agent/pull/32).
- [ ] Human verification (pending).

# Issue #9 progress

Owner: sole Issue #9 worker, branch `feature/issue-9-doctor`.

No existing todo.md or AGENTS-designated progress file was present at implementation start.
Detailed acceptance evidence and reproduction steps belong in the PR body and attachments.

- [x] Inspect base/worktree, dependency behavior, and reserved device ownership.
- [x] Implement doctor and pass automated checks (179 tests, analyze clean).
- [x] Verify example on reserved Simulator (50 CLI calls; five images inspected; teardown complete).
- Publication status and inspected Draft PR URL are recorded in the coordinator's `worker-9-result.md`.
- [ ] Human verification (pending).
# Issue #10 progress

- Owner: Issue #10 sole worker (coordinator-requested gpt-6-astra, medium).
- Branch: `feature/issue-10-snapshot-filter`.
- [x] Implement snapshot filters and full-observation ref safety.
- [x] Update SPEC, ARCHITECTURE, Japanese CLI reference and help.
- [x] Add automated regression scenarios; format and analyze pass.
- [x] Full suite: 169 tests passed with `dart test --concurrency=1`, original deadlines.
- [x] Reserved Simulator: 47 records passed, text/JSON and real collision fixture.
- [x] Inspect four final screenshots; complete app/daemon/runner/Simulator teardown.
- Draft publication, exact head and attachments: tracked in worker handoff and PR body.
- [ ] Human verification (pending).

No pre-existing todo.md was present when implementation began. The coordinator
released the initial phase boundary for Simulator verification and Draft publication.
# Progress

- Issue #7: worker-7 (gpt-6-astra, medium). Implementation, 168 automated tests, live text/JSON Simulator verification and teardown passed.
- Draft PR handoff prepared; human verification remains pending.

# Issue #4 progress

- Owner: Issue #4 sole worker (gpt-6-astra / medium requested).
- Implementation: get text, box, count and shared read resolution complete.
- Automated verification: dart format ., dart analyze, dart test passed (171 tests).
- Simulator verification: 29 product CLI calls plus missing-text checks passed; both screenshots inspected. Owned runner/session stopped and simulator returned to Shutdown.
- Details and human reproduction: see the PR body and attachments.
- Verified code: `6010ee567ff0af4ddb04586b7fde166a8f1f7462`.
- Draft PR handoff: agent verification complete; human verification remains pending.
# Issue #5 progress

- Owner: sole Issue #5 worker (gpt-6-astra; medium reasoning requested).
- Branch: `feature/issue-5-is-visible`.
- Existing progress file was absent at implementation start; this file records the work.
- Implementation: read-only `is visible`, shared target re-observation, nullable result.
- Implementation commit: `0fc5785f7bd7fc2c67a60a3574f663c479142852`.
- `dart format .` and `dart analyze`: passed. `dart test --concurrency=1`:
  all 168 tests passed in 1m31s after shared-host load decreased; no skips.
- Simulator: all text/JSON scenarios passed, before/after images opened and
  byte-identical; fixture state unchanged; assigned device returned to Shutdown.
- Commands, expected/actual results, evidence and human steps belong in the PR body and attachments.
- Human verification remains pending.

# Issue #6: close --all

担当: Issue #6 worker / feature/issue-6-close-all

- [x] 既存AGENTS.mdにtodo.md指定・ファイルがないことを確認し、本記録を整備。
- [x] 契約: close --allは全体操作、明示--sessionとの併用はINVALID_ARGUMENT。受付時に全sessionを固定し新規要求を拒否。既存queueを共通deadlineまで待ち、期限超過では接続世代を失効する。送信済み操作はunknown、queue待ちはnot_sent。UI操作は再送しない。
- [x] 結果: session:null、成功data.sessionsにsession別Result。部分失敗はerror.details.sessions、期限超過はexit 5、他の切断失敗はexit 1。全sessionのローカルrefとURI所有権を破棄しdaemon終了。アプリ自体は終了しない。daemon不在は空配列で成功。
- [x] Simulator: 2アプリ、text/JSON各close、未接続・冪等・再connect・画面保持を38 CLI呼出しで確認。4画像を目視し、runner/アプリ停止・両端末Shutdownを確認。
- [x] dart format .、dart analyze（No issues found）、全dart test（--concurrency=1、171件）成功。
- [x] Draft PR用の検証記録・人間の再現手順・4画像を準備。
- [ ] 人間確認（Draft PRで引き渡し）。

詳細な検証記録はPR本文と添付に残す。
