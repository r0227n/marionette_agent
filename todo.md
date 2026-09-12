# Issue #10 progress

- Owner: Issue #10 sole worker (coordinator-requested gpt-6-astra, medium).
- Branch: `feature/issue-10-snapshot-filter`.
- Progress record: [Issue #10 verification](packages/marionette_agent/docs/verification/issue-10.md).
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
