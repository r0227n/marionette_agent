# Recovery and cleanup

Inspect `workflow.sh status <run>`, the task files and the actual resources before
resuming. State files record observations, not proof that a process has stopped.
The helper deliberately does not restart agents, retry mutations, merge conflicts
automatically, or remove worktrees on completion.

| Situation | Action |
| --- | --- |
| `preparing` failed | Inspect Issue/base/remote and gtr inventories; repair the cause. Retain the task directory. Prepare a new attempt with a separate `state_root` only after ruling out live work or an existing PR. |
| `scoped-input` | Review/write `task.md`, then run `work`. |
| Container/agent failure or interruption | Inspect the recorded container with `docker inspect`, logs and gtr inventory inside it. Confirm it stopped. Preserve any partial result. A new attempt needs an explicit implementation decision; failure does not authorize blindly rerunning actions. |
| `result-ready` | Review the patch, then collect. If gtr failed, inspect `git gtr list --porcelain` and its log before retrying; creation may have left a branch/worktree. |
| `host-created` or patch conflict | Use the recorded host path and complete a manual reviewed handoff. Keep existing changes. Once the exact result is staged and reviewed, record phase `collected` and run host verification. Never reset another actor's work to make a patch apply. |
| Busy resource | No acceptance command has started. Wait for its owner to finish, then retry `verify`. |
| `verification-failed` | Read the log, correct/review/stage changes in the host worktree, then `verify`. |
| `verifying` after interruption | Confirm all related host processes, servers and device sessions stopped. Finish media capture/cleanup. Only then remove that run's resource lock directories, record phase `verification-failed`, and rerun acceptance. |
| `verified` with new edits | Review/stage and `verify` again. Old verification does not cover new content. |
| `committed` | Confirm clean worktree, recorded commit and verified tree. `publish` can continue if no PR exists. If content changed, re-verify through a reviewed recovery rather than editing `verified_tree`. |
| `publishing`, nonzero/uncertain gh result | Read `pr-create.out`, `pr-create.err`, `published-pr.json` and `pr.json`. Query all PR states for the exact head/base. Record any existing URL before another action. Repair that PR; never create a replacement. |

For a partially published PR, compare the current head with `code_commit` and
`verified_tree`. Read the latest body and preserve human edits and uploaded URLs.
Inspect which selected attachments uploaded. If only media is missing, check
`gh pr edit --help` for `--attach` and upload only the confirmed missing files to
the existing PR. Video paths have no `#alt` suffix. Re-read the body after each
attempt, since uploads can partly succeed. Retry only a diagnosed transient
failure. Missing capability/access or a repeated failure leaves publication
incomplete and the existing URL must be returned with the missing items.

For a stale `operation.lock`, confirm no workflow process for that task is running
before removing the empty directory. Resource lock `owner` files identify PID and
task; PID reuse means absence/presence alone is insufficient to decide ownership.
Never release another run's lock or rely on elapsed time as proof of termination.

## Explicitly requested cleanup

Worktree cleanup always goes through gtr. Inspect status first, retain needed
evidence, and use `git -C <source> gtr rm <branch>` for the host worktree. Container
worktrees can be listed/removed with `docker exec <container> git -C
/tmp/cip/repo gtr list --porcelain` / `gtr rm <branch>` while the container runs.
Avoid `--force`, branch deletion and bulk cleanup unless the request covers them.

After confirming the container's `container-issue-pr.run` label matches this run
and it is stopped, an authorized cleanup can use `docker rm <recorded-container>`.
Deleting a container also deletes its local worktree storage; preserve the patch
and needed evidence first. Remove task artifacts only when they are no longer
needed for human verification or publication recovery.
