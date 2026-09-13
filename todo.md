# Progress

- Issue #7: worker-7 (gpt-6-astra, medium). Implementation, 168 automated tests, live text/JSON Simulator verification and teardown passed.
- Record: [Issue #7 verification](packages/marionette_agent/docs/verification/issue-7.md).
- Draft PR handoff prepared; human verification remains pending.

# Issue #4 progress

- Owner: Issue #4 sole worker (gpt-6-astra / medium requested).
- Implementation: get text, box, count and shared read resolution complete.
- Automated verification: dart format ., dart analyze, dart test passed (171 tests).
- Simulator verification: 29 product CLI calls plus missing-text checks passed; both screenshots inspected. Owned runner/session stopped and simulator returned to Shutdown.
- Details and human reproduction: [Issue #4 verification](packages/marionette_agent/docs/verification/issue-4.md).
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
- Commands, expected/actual results, evidence and human steps:
  [Issue #5 verification](packages/marionette_agent/docs/verification/issue-5.md).
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

詳細な検証記録は packages/marionette_agent/docs/verification/issue-6.md に記録する。
