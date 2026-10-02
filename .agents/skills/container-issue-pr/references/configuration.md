# Configuration and boundaries

Use the complete [example](../assets/config.example.json). The helper validates
types with `scripts/config.jq`; a task receives a frozen copy in `config.json`.
Change the external config for new tasks. For an existing task, use the recovery
procedure instead of silently changing the execution contract.

| Setting | Contract |
| --- | --- |
| `source` | Absolute root of a clean, full Git checkout. HEAD must equal the fetched `remote/base`. Commit and merge outstanding changes first. |
| `state_root` | Absolute host directory outside the source. Contains one `owner-repo-issue-N` directory per task, including filtered snapshots, logs and patches. |
| `lock_root` | Absolute shared host directory; use the same directory across repositories and configs sharing hardware/ports. |
| `repository`, `remote`, `base` | GitHub.com `owner/repo`, matching Git remote, and PR base. SSH and HTTPS GitHub.com remotes are supported. |
| `branch_prefix` | Creates `<prefix>/issue-N` in both environments. Do not reuse the branch for a different task. |
| `parallelism` | Integer 1–32; maximum jobs per batch. Separate invocations do not share a global container quota. |
| `container` | Prebuilt image, Docker network, CPU/memory limits and optional absolute `env_file`. Docker-compatible engines work; Colima is optional. |
| `agent.argv` | Nonempty array of literal command arguments. Runs in the container worktree with the task on stdin; use a wrapper in the image if the chosen CLI needs a different input format. |
| `copy.exclude` | rsync exclude patterns applied to both input and returned output. Defaults omit common build caches and dotenv files. Git metadata is always excluded. |
| `copy.extra` | Explicit repository-relative files/directories to copy in addition to tracked files, including ignored local files. Exclusions still apply. Never `..`, absolute paths or `.git`. |
| `host.resources` | Shared resource names, e.g. `simulator-UDID` and `port-8010`. Default `host-runtime` serializes host acceptance. Empty is suitable only for isolated checks. |
| `host.env` | Explicit string environment variables for host checks, e.g. assigned device ID, session and port. Host commands also inherit the invoking environment. |
| `host.commands` | Ordered checks with `name`, worktree-relative `cwd` and literal `argv`. At least one meaningful acceptance command is required. A cwd resolving outside the worktree is rejected. |
| `pr.evidence` | `required`, or `waived` with a nonempty `waiver_reason` when screenshots/video cannot demonstrate the change. |

Command arrays are passed directly, without `eval` or sourcing the JSON file.
To run shell syntax deliberately, use `['bash', '-c', '...']` (JSON uses double
quotes) or preferably a reviewed script. Keep secrets out of command arguments,
task text and committed config. Agent and verification logs can contain command
output, so inspect them before sharing. `container.env_file` is passed to Docker
explicitly; the helper does not copy the host's home directory, credentials,
Docker socket or Git metadata into the container.

## Images and copies

The image must already contain `/bin/bash`, Git, `git-gtr` 2.11+ and the selected
noninteractive agent CLI. It must allow writing under `/tmp`. Install gtr using
its official installation instructions when building your image; pin the image
and tool versions for repeatable environments. The helper uses the Docker CLI,
so choose the desired Docker context before invocation. Remote daemons also use
explicit `docker cp`; the helper does not depend on source bind mounts.

Container worktrees are seeded from an empty container-owned Git repository.
After gtr creates the Issue worktree, the filtered host snapshot is copied in
and committed locally as its baseline. Original host history and remotes are
not present in that repository. The agent can edit and commit normally; the
returned patch is calculated from file contents against the host-side filtered
baseline, so all final file changes are captured regardless of agent commits.
Excluded files in the full host worktree are preserved, not interpreted as
deletions. Renames may be represented as delete/add with equivalent contents.
Ignored `copy.extra` files are input context. If an agent modifies one that is
absent from the host Git baseline, patch application stops for review; it does
not silently add that local-only file to the PR.

Submodules and sparse source checkouts are outside the initial supported scope.
File contents, executable bits, relative symlinks and binary changes use Git's
normal patch semantics; ownership, timestamps and empty directories are not PR
content. Keep filenames and extra-copy rules portable across host/container
filesystems. Case-only path collisions on case-insensitive hosts need manual
resolution. Copies should be made while the source is idle: pre/post Git checks
detect ordinary edits, but do not lock an external editor or ignored extra files.

## gtr and host setup

Creation uses `git gtr new ... --porcelain --no-fetch --no-copy --no-hooks
--no-sparse --track none`, with an explicitly pinned base. The helper owns copying
and runs setup inside host resource locks, so gtr copying/hooks are disabled
deliberately. Both `hook_status` values are recorded as `disabled`.
Put every required dependency/setup operation from the repository's gtr hooks
into `host.commands`, followed by actual acceptance checks. This does not grant
trust to repository hooks. Never run `git gtr trust` automatically.

Sources: [Agent Skills format](https://agentskills.io/specification),
[gtr agent lifecycle](https://github.com/coderabbitai/git-worktree-runner/blob/main/docs/agent-usage.md),
[Docker copy semantics](https://docs.docker.com/reference/cli/docker/container/cp/).
