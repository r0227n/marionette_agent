---
name: issue-create
description: Create GitHub feature or bug issues from the repository's ISSUE_TEMPLATE using the gh CLI. Use for a requested task or an explicit request to turn a candidate list into issues; use triage workflows to manage existing issues.
---

# Issue Create

Turn requested tasks into implementation-ready GitHub Issues that follow the current repository template.

## Workflow

1. Resolve the target repository from the current clone. Read its agent instructions, issue-tracker guidance, and `.github/ISSUE_TEMPLATE/` before drafting. Select `feature.yml` for new behavior or improvement and `bug.yml` for broken behavior. If the category is genuinely ambiguous, ask the user to choose.
2. Gather facts from the relevant specification, architecture, task list, code, and existing Issues. Report missing references without inventing their contents. Search open and closed Issues for duplicates, covering the relevant history beyond any truncated listing. For a candidate list, select independently completable outcomes and record each candidate as create, covered, unnecessary, or deferred with a reason. Skip confirmed duplicates and continue unrelated items; ask only when uncertain overlap materially changes the scope. Distinguish upstream prerequisites from capabilities available today.
3. Draft one Issue per selected outcome, including every non-Markdown field in the selected Issue Form. Render each field's `attributes.label` as a Markdown heading and supply its answer beneath it. Keep the title concise and outcome-oriented, without a `[Feature]` or `[Bug]` prefix. State:
   - the purpose and user-visible outcome;
   - enough background and current behavior to understand the task;
   - the in-scope work and explicit exclusions;
   - observable, exhaustive completion criteria as checkboxes;
   - verification that demonstrates the outcome.
4. For a draft request, show the title, category, label, and rendered body and wait for publication approval. An explicit request to create or publish authorizes publication within that scope; honor authorization already given in the conversation. For an authorized batch, briefly explain selection and grouping, then proceed.
5. Publish with `gh issue create`, passing the rendered body through `--body-file` and applying exactly one category label: `feature` or `bug`. Capture each created Issue URL immediately, then read it back with `gh issue view` to verify the title, body, and label. If creation has an uncertain result, check whether it succeeded before retrying. Report created URLs and skipped/deferred candidates with reasons.

## Boundaries

- Create one Issue for a single task by default. An explicit request to create issues from a list authorizes splitting independent outcomes and grouping inseparable options; ask before expanding beyond that list or splitting a requested single Issue.
- Treat the checked-in template as the source of truth. If the selected template or label is missing, report the mismatch and stop before publishing.
- Ask only for decisions or missing product intent. Find repository facts directly.
- Preserve uncertainty explicitly; do not invent reproduction results, implementation details, or acceptance criteria unsupported by the repository or user.
- Do not assign users, add projects or milestones, create relationships, or modify existing Issues unless the user requests it.
