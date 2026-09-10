---
name: pr-create
description: Create a new GitHub draft pull request with gh, repository-required verification, and relevant image or video evidence. Use when asked to create or open a PR; use a different workflow to modify an existing PR.
---

# PR Create

Create one evidence-backed draft pull request whose body follows the repository template. Minimize questions by deriving the title, summary, verification, and evidence from the repository and current task.

## Workflow

1. Read the repository instructions and `.github/pull_request_template.md`. Treat the template headings as the required body contract. Stop if the template is missing or does not require `概要`, `動作確認方法`, and `エビデンス`.
2. Inspect the current branch, `develop...HEAD` diff, commits, relevant specifications, and task history. Require a non-empty change on a non-`develop`, non-detached branch. Derive a concise title and substantive content for every template section; ask only for intent that cannot be established from those sources.
3. For issue-backed work, link the single target issue and map its acceptance criteria to the change and verification. For work without an issue, use the task branch selected by the repository instructions; do not create a worktree solely to publish.
4. Run every verification required by the repository instructions and the changed area. Record commands or manual steps, expected results, and actual results under `動作確認方法`. Use [simulator-verify](../simulator-verify/SKILL.md) when this repository requires example/Simulator verification. Reuse checks performed on the same code during this task; rerun affected checks and evidence after code changes. Record the verified commit (or the verified code commit plus documentation-only follow-up commits). Stop before publishing when a required check fails or a required environment check cannot be completed.
5. Resolve evidence before changing remote state:
   - Evidence is required for UI or runtime behavior changes. Prefer paths supplied by the user, then media produced during the current task, then relevant image or video files in the worktree and task-related temporary output. Inspect candidate contents and attach every candidate that clearly demonstrates the post-change behavior, up to 50 files. Do not select by filename or modification time alone.
   - Each attachment must exist, be a regular image or video file, and be converted to an absolute path. If no relevant candidate exists, capture it using the available app/Simulator tools. Ask for a path only when required evidence cannot be obtained with available access; report the exact obstacle and leave the PR unpublished.
   - Before pushing an evidence-required PR, check that the installed `gh pr create --help` supports `--attach`. If unavailable, keep the prepared result and report the missing capability; do not silently omit evidence.
   - Waive attachments only when the diff is documentation-only or image/video cannot meaningfully demonstrate the change. Difficulty alone is not grounds for a waiver. When applicability is uncertain, require evidence. For a waiver, write the concrete reason under `エビデンス`.
6. Require a clean worktree before publishing. Commit the task's reviewed changes when needed; preserve unrelated user changes. If a tracked file mixes task and unrelated hunks, use patch-based staging; never stage or commit that whole path. Follow the repository rule for issue worktrees versus non-issue task branches. Inspect the complete staged diff before committing, then verify that the commit contains only task changes and unrelated changes remain intact. Ask only when the changes cannot be safely separated using the available task context. Untracked files selected solely as PR attachments are the only permitted exception.
7. Check all PR states for an existing PR with the same head branch and base `develop`. If one exists, return its URL and do not create another. For an interrupted publication from this authorized task, use the recovery procedure below to finish the same PR. Fetch enough remote state to detect whether the branch can be pushed normally. Push it with `git push -u origin HEAD` when needed; stop on a remote-ahead or diverged branch and never force-push.
8. Render a temporary body from `.github/pull_request_template.md`, replacing its prompts with the derived summary, verification, and evidence description or waiver. Confirm all three sections contain real content. Under `動作確認方法`, separate the agent's actual results from human reproduction steps (reset, launch/connect, operations, expected screen/state); for documentation, provide review files and criteria. Leave the human verification checkbox unchecked. Include the issue URL when applicable without claiming the issue is already closed. Create the PR with `gh pr create --draft --base develop --title <title> --body-file <body-file>`. For an evidence-required PR, add one `--attach <absolute-path>` argument for every selected file; creating without all selected attachments is not allowed.
9. Capture the URL immediately. Read the PR back with `gh pr view` and verify its base is `develop`, it is a draft, its body contains the three completed sections, the human verification remains pending, its head matches the verified code and any documentation-only follow-up, and the attachments appear in the body when required. `gh pr create` can create a PR even when only some uploads succeed; on any non-zero or uncertain result, inspect the existing PR before retrying and use the recovery procedure below. Never create a replacement duplicate.

Report the PR URL, attached evidence or waiver reason, verification performed, and any remaining limitation.

Keep the PR draft for human verification. Ready conversion, merge, manual issue closure, and worktree removal require a separate request.

## Interrupted publication

Apply this only to completing a publication already authorized in this task, including a resumed task with its prior publication record. General revisions to an existing PR remain a separate workflow.

1. Record the URL, head commit, selected attachment paths, uploaded URLs, and unresolved results in the task's handoff record. Read the existing PR and reconcile these with its body and actual head. If creation status is uncertain, resolve it using the exact head/base before any create retry.
2. When only evidence is missing, inspect `gh pr edit --help` for `--attach`, then run `gh pr edit <url> --attach <missing-absolute-path>` for the confirmed missing files, without replacing the existing body. Keep already uploaded assets. Re-read after every attempt, because edit can also partially succeed. If upload identity is uncertain, inspect the body/media before uploading again.
3. If creation produced an incomplete body, read its latest version and preserve human edits and uploaded URLs while adding this task's missing sections with `--body-file`. If another actor changed the head, compare it with the verified code and rerun affected checks before claiming completion.
4. Retry only a diagnosed transient failure after the reconciliation above. If the same failure recurs or access/capability is missing, return the existing URL, missing items, and exact obstacle as incomplete. Never create a replacement PR to repair publication.
