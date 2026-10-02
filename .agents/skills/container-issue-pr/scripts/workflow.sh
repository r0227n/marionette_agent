#!/usr/bin/env bash
# Bash 3.2+, Git, git-gtr 2.11+, jq, rsync, Docker and gh. Run on the host.
set -eo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
TASK_LOCK= CONTAINER_OWNED= IN_FLIGHT=0
RESOURCE_LOCKS=()
BATCH_ACTIVE=0
PIDS=()

die() { printf 'container-issue-pr: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null || die "Missing executable: $1"; }
json() { jq -er "$1" "$RUN/config.json"; }
value() { jq -er --arg k "$1" '.[$k]' "$RUN/state.json"; }
record() {
  jq --arg k "$1" --arg v "$2" '.[$k]=$v' "$RUN/state.json" > "$RUN/state.tmp.$$"
  mv "$RUN/state.tmp.$$" "$RUN/state.json"
}
phase() { record phase "$1"; note "issue $(value issue): $1"; }
require_phase() { [ "$(value phase)" = "$1" ] || die "Expected phase $1; inspect $RUN/state.json"; }
clean() { [ -z "$(git -C "$1" status --porcelain --untracked-files=all)" ] || die "Uncommitted files in $1"; }
unchanged() {
  [ "$(git -C "$WORKTREE" symbolic-ref --short HEAD)" = "$(value branch)" ] || die 'Worktree branch changed'
  [ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$1" ] || die 'Worktree HEAD changed'
  git -C "$WORKTREE" diff --quiet -- || die 'Unstaged changes; review/stage and verify again'
  [ -z "$(git -C "$WORKTREE" ls-files --others --exclude-standard)" ] || die 'Untracked files; review them before verification'
}
finish() {
  local rc=$? lock pid
  if [ "$BATCH_ACTIVE" = 1 ]; then
    for pid in "${PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
  fi
  if [ -n "$CONTAINER_OWNED" ]; then
    docker stop -t 10 "$CONTAINER_OWNED" >/dev/null 2>&1 || note "Container may still be running: $CONTAINER_OWNED"
  fi
  if [ "$IN_FLIGHT" = 0 ]; then
    for lock in "${RESOURCE_LOCKS[@]}"; do
      rm -f "$lock/owner"
      rmdir "$lock" || true
    done
  elif [ "${#RESOURCE_LOCKS[@]}" -gt 0 ]; then
    note 'Host command interrupted: resource locks retained. Confirm all child processes stopped before releasing locks.'
  fi
  if [ -n "$TASK_LOCK" ]; then rmdir "$TASK_LOCK" || true; fi
  exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# JSON argv arrays are passed as arguments, never evaluated as shell source.
read_args() {
  ARGS=()
  while IFS= read -r -d '' item; do ARGS+=("$item"); done < <(jq -j "$1 | .[] | ., \"\u0000\"" "$2")
}
validate_config() {
  jq -e -f "$SCRIPT_DIR/config.jq" "$1" >/dev/null || die 'Invalid configuration; see assets/config.example.json'
  git check-ref-format --branch "$(jq -r .base "$1")" >/dev/null
  git check-ref-format --branch "$(jq -r .branch_prefix "$1")/issue-1" >/dev/null
}
load() {
  RUN=$(cd "$1" && pwd -P)
  [ -f "$RUN/state.json" ] && [ -f "$RUN/config.json" ] || die 'Not a task directory'
  validate_config "$RUN/config.json"
  SOURCE=$(json .source)
  REPOSITORY=$(json .repository)
  mkdir "$RUN/operation.lock" 2>/dev/null || die "Task is busy: $RUN/operation.lock"
  TASK_LOCK="$RUN/operation.lock"
}
remote_matches() {
  local url
  url=$(git -C "$SOURCE" remote get-url "$(json .remote)")
  case "$url" in
    "https://github.com/$REPOSITORY"|"https://github.com/$REPOSITORY.git"|"git@github.com:$REPOSITORY"|"git@github.com:$REPOSITORY.git") ;;
    *) die 'Configured repository and Git remote differ (GitHub.com remotes supported)' ;;
  esac
}
pr_lookup() {
  gh pr list --repo "$REPOSITORY" --state all --head "$(value branch)" --base "$(json .base)" \
    --json url,state,isDraft,headRefOid,headRefName,baseRefName > "$RUN/existing-pr.json"
  [ "$(jq length "$RUN/existing-pr.json")" = 0 ] || {
    jq -r '.[].url' "$RUN/existing-pr.json"
    die 'Existing PR found. Inspect/recover that PR; do not create a duplicate.'
  }
}
parse_gtr() {
  # gtr porcelain escapes backslashes, tabs and newlines. Decode as data.
  local key encoded decoded got_branch= got_hook=
  GTR_PATH= GTR_HOOK=
  while IFS=$'\t' read -r key encoded; do
    decoded=$(printf '%b' "$encoded")
    case "$key" in
      path) GTR_PATH=$decoded ;;
      branch) got_branch=$decoded ;;
      hook_status) got_hook=$decoded ;;
      *) die 'Unexpected gtr porcelain record' ;;
    esac
  done < "$1"
  case "$GTR_PATH" in /*) ;; *) die 'gtr did not return an absolute path' ;; esac
  case "$GTR_PATH" in *$'\n'*|*$'\r'*|*$'\t'*) die 'Control characters in worktree paths are unsupported' ;; esac
  [ "$got_branch" = "$(value branch)" ] || die 'gtr returned a different branch'
  case "$got_hook" in ran|none|disabled) GTR_HOOK=$got_hook ;;
    skipped-untrusted|partial) die 'gtr hooks need review; never run git gtr trust automatically' ;;
    *) die 'Missing/unknown gtr hook status' ;;
  esac
}
exclusions() {
  # Also protect Git metadata when Linux results return to a case-insensitive host.
  EXCLUDES=(--exclude='.[gG][iI][tT]')
  while IFS= read -r -d '' item; do EXCLUDES+=("--exclude=$item"); done < <(jq -j '.copy.exclude[] | ., "\u0000"' "$RUN/config.json")
}
snapshot() {
  local extra
  clean "$SOURCE"
  [ "$(git -C "$SOURCE" rev-parse HEAD)" = "$(value base_commit)" ] || die 'Source HEAD changed since prepare'
  git -C "$SOURCE" ls-files -s | awk '$1 == "160000" {found=1} END {exit !found}' && die 'Submodules are unsupported; use a regular source checkout'
  mkdir "$RUN/input"
  git -C "$SOURCE" ls-files -z > "$RUN/tracked-files"
  exclusions
  rsync -rlpt --from0 --files-from="$RUN/tracked-files" "${EXCLUDES[@]}" "$SOURCE/" "$RUN/input/"
  while IFS= read -r -d '' extra; do
    [ -e "$SOURCE/$extra" ] || [ -L "$SOURCE/$extra" ] || die "Missing extra copy path: $extra"
    case "$(cd "$(dirname "$SOURCE/$extra")" && pwd -P)/" in "$SOURCE/"*) ;; *) die 'Extra copy path escapes the source' ;; esac
    (cd "$SOURCE" && rsync -rlptR "${EXCLUDES[@]}" "$extra" "$RUN/input/")
  done < <(jq -j '.copy.extra[] | ., "\u0000"' "$RUN/config.json")
  clean "$SOURCE"
  [ "$(git -C "$SOURCE" rev-parse HEAD)" = "$(value base_commit)" ] || die 'Source changed during copy'
  # The local diff repository captures only the filtered files; excluded host files
  # cannot become accidental deletions when the result is applied to the full tree.
  mkdir "$RUN/result"
  rsync -rlpt "$RUN/input/" "$RUN/result/"
  git -C "$RUN/result" init -q
  git -C "$RUN/result" add -f --all
  git -C "$RUN/result" -c user.name=Snapshot -c user.email=snapshot@localhost -c core.hooksPath=/dev/null commit -qm baseline --allow-empty
  record snapshot_commit "$(git -C "$RUN/result" rev-parse HEAD)"
}

prepare() {
  local config number root branch source_commit
  config=$1
  validate_config "$config"
  REPOSITORY=$(jq -r .repository "$config")
  number=${2#\#}
  case "$number" in https://github.com/"$REPOSITORY"/issues/*) number=${number##*/} ;; esac
  [[ "$number" =~ ^[1-9][0-9]*$ ]] || die 'Supply an issue number or matching GitHub issue URL'
  SOURCE=$(jq -r .source "$config")
  [ "$(cd "$SOURCE" && pwd -P)" = "$(git -C "$SOURCE" rev-parse --show-toplevel)" ] || die 'source must be the repository root'
  clean "$SOURCE"
  [ "$(git -C "$SOURCE" config --bool core.sparseCheckout || true)" != true ] || die 'Sparse source checkouts are unsupported'
  root=$(jq -r .state_root "$config")
  mkdir -p "$root"
  root=$(cd "$root" && pwd -P)
  case "$root/" in "$SOURCE/"*) die 'state_root must be outside the source checkout' ;; esac
  RUN="$root/${REPOSITORY//\//-}-issue-$number"
  mkdir "$RUN" || die 'Task already exists; inspect its state instead of overwriting'
  cp "$config" "$RUN/config.json"
  branch="$(json .branch_prefix)/issue-$number"
  jq -n --arg issue "$number" --arg branch "$branch" '{issue:$issue,branch:$branch,phase:"preparing"}' > "$RUN/state.json"
  load "$RUN"
  remote_matches
  pr_lookup
  gh api "repos/$REPOSITORY/issues/$number" > "$RUN/issue.json"
  jq -e '.state == "open" and (has("pull_request") | not)' "$RUN/issue.json" >/dev/null || die 'Target must be an open Issue, not a PR'
  [ "$(jq '.issue_dependencies_summary.blocked_by // 0' "$RUN/issue.json")" = 0 ] || die 'Issue has open blockers'
  gh api --paginate --slurp "repos/$REPOSITORY/issues/$number/comments" | jq 'add // []' > "$RUN/comments.json"
  git -C "$SOURCE" fetch "$(json .remote)" "$(json .base)"
  source_commit=$(git -C "$SOURCE" rev-parse HEAD)
  [ "$source_commit" = "$(git -C "$SOURCE" rev-parse "$(json .remote)/$(json .base)")" ] || die 'Source HEAD must equal the fetched base; commit/merge source changes before starting'
  record base_commit "$source_commit"
  git -C "$SOURCE" gtr list --porcelain > "$RUN/host-worktrees.before"
  phase scoped-input
  printf '%s\n' "$RUN"
}

work() {
  local container cw env_file owner
  load "$1"
  require_phase scoped-input
  [ -s "$RUN/task.md" ] || die 'Write task.md from the Issue and acceptance criteria before work'
  need docker
  docker info >/dev/null
  container="cip-$(date +%s)-$$-${RANDOM}"
  record container "$container"
  env_file=$(jq -r '.container.env_file // empty' "$RUN/config.json")
  ARGS=()
  [ -z "$env_file" ] || ARGS+=(--env-file "$env_file")
  phase container-starting
  docker create --name "$container" --label "container-issue-pr.run=$RUN" \
    --init --network "$(json .container.network)" --cpus "$(json .container.cpus)" \
    --memory "$(json .container.memory)" "${ARGS[@]}" --entrypoint /bin/bash "$(json .container.image)" \
    -c 'trap "exit 0" TERM INT; while :; do sleep 1 & wait "$!" || :; done' > "$RUN/container.id"
  CONTAINER_OWNED=$container
  docker start "$container" >/dev/null
  docker exec "$container" bash -c '
    set -e
    command -v git-gtr >/dev/null
    mkdir -p /tmp/cip/control /tmp/cip/repo
    git -C /tmp/cip/repo init -q
    git -C /tmp/cip/repo -c user.name=Snapshot -c user.email=snapshot@localhost -c core.hooksPath=/dev/null commit -qm seed --allow-empty
    git -C /tmp/cip/repo gtr new "$1" --from HEAD --track none --no-fetch --no-copy --no-hooks --no-sparse --porcelain
  ' -- "$(value branch)" > "$RUN/container-gtr.tsv" 2> "$RUN/container-gtr.log"
  parse_gtr "$RUN/container-gtr.tsv"
  cw=$GTR_PATH
  record container_worktree "$cw"
  record container_hook_status "$GTR_HOOK"
  # Sequence is deliberate: create the container worktree, then copy host files.
  snapshot
  owner="$(docker exec "$container" id -u):$(docker exec "$container" id -g)"
  docker cp "$RUN/input/." "$container:$cw/"
  docker cp "$RUN/task.md" "$container:/tmp/cip/control/task.md"
  docker exec -u 0 "$container" chown -R "$owner" "$cw" /tmp/cip/control
  docker exec "$container" bash -c '
    set -e
    git -C "$1" add -f --all
    git -C "$1" -c user.name=Snapshot -c user.email=snapshot@localhost -c core.hooksPath=/dev/null commit -qm host-snapshot --allow-empty
  ' -- "$cw"
  read_args '.agent.argv' "$RUN/config.json"
  phase agent-running
  if docker exec -w "$cw" "$container" bash -c 'exec "$@" < /tmp/cip/control/task.md' -- "${ARGS[@]}" > "$RUN/agent.log" 2>&1; then
    phase agent-succeeded
  else
    phase agent-failed
    die "Agent failed; inspect $RUN/agent.log. No automatic retry."
  fi
  mkdir "$RUN/output"
  docker cp "$container:$cw/." "$RUN/output/"
  exclusions
  rsync -rlpt --delete "${EXCLUDES[@]}" "$RUN/output/" "$RUN/result/"
  git -C "$RUN/result" add -f --all
  git -C "$RUN/result" -c core.quotePath=true diff --cached --binary --full-index --no-ext-diff --no-textconv "$(value snapshot_commit)" -- > "$RUN/result.patch"
  [ -s "$RUN/result.patch" ] || die 'Agent produced no eligible file changes'
  phase result-ready
}

collect() {
  load "$1"
  require_phase result-ready
  git -C "$SOURCE" gtr new "$(value branch)" --from "$(value base_commit)" --track none \
    --no-fetch --no-copy --no-hooks --no-sparse --porcelain > "$RUN/host-gtr.tsv" 2> "$RUN/host-gtr.log"
  parse_gtr "$RUN/host-gtr.tsv"
  WORKTREE=$GTR_PATH
  record host_worktree "$WORKTREE"
  record host_hook_status "$GTR_HOOK"
  phase host-created
  clean "$WORKTREE"
  [ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$(value base_commit)" ] || die 'Host worktree has a different base'
  git -C "$WORKTREE" apply --check --index "$RUN/result.patch"
  git -C "$WORKTREE" apply --index "$RUN/result.patch"
  phase collected
  printf '%s\n' "$WORKTREE"
}

verify() {
  local tree head lock root resource count i cwd name rc
  load "$1"
  case "$(value phase)" in collected|verification-failed|verified) ;; *) die 'Collect results before verification' ;; esac
  WORKTREE=$(value host_worktree)
  head=$(git -C "$WORKTREE" rev-parse HEAD)
  [ "$head" = "$(value base_commit)" ] || die 'Host HEAD changed before verification'
  unchanged "$head"
  tree=$(git -C "$WORKTREE" write-tree)
  root=$(json .lock_root)
  mkdir -p "$root"
  while IFS= read -r resource; do
    lock="$root/$resource.lock"
    mkdir "$lock" 2>/dev/null || die "Resource busy: $lock (verification has not started)"
    RESOURCE_LOCKS+=("$lock")
    printf '%s\n%s\n' "$$" "$RUN" > "$lock/owner"
  done < <(jq -r '.host.resources | unique | sort | .[]' "$RUN/config.json")
  phase verifying
  : > "$RUN/verification.log"
  count=$(jq '.host.commands | length' "$RUN/config.json")
  ENV_ARGS=()
  while IFS= read -r -d '' item; do ENV_ARGS+=("$item"); done < <(jq -j '.host.env | to_entries[] | (.key + "=" + .value), "\u0000"' "$RUN/config.json")
  for ((i=0; i<count; i++)); do
    cwd=$(jq -r ".host.commands[$i].cwd" "$RUN/config.json")
    cwd=$(cd "$WORKTREE/$cwd" && pwd -P)
    case "$cwd/" in "$WORKTREE/"*) ;; *) die 'Host command cwd escapes the worktree' ;; esac
    name=$(jq -r ".host.commands[$i].name" "$RUN/config.json")
    read_args ".host.commands[$i].argv" "$RUN/config.json"
    printf '\n>>> %s\n' "$name" >> "$RUN/verification.log"
    IN_FLIGHT=1
    rc=0
    (cd "$cwd" && env "${ENV_ARGS[@]}" CIP_RUN_DIR="$RUN" CIP_WORKTREE="$WORKTREE" "${ARGS[@]}") >> "$RUN/verification.log" 2>&1 || rc=$?
    IN_FLIGHT=0
    if [ "$rc" -ne 0 ]; then phase verification-failed; die "Host check failed: $name (exit $rc)"; fi
    printf 'PASS: %s\n' "$name" >> "$RUN/verification.log"
  done
  phase verification-failed
  unchanged "$head"
  [ "$(git -C "$WORKTREE" write-tree)" = "$tree" ] || die 'Index changed during verification; review and verify again'
  record verified_tree "$tree"
  record verified_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  phase verified
}

publish() {
  local title body tree commit attachment mime rc
  load "$1"
  title=$2 body=$3
  case "$(value phase)" in verified|committed) ;; *) die 'Successful host verification is required before publication' ;; esac
  [ -n "$title" ] && [ -s "$body" ] || die 'Supply a title and completed PR body file'
  WORKTREE=$(value host_worktree)
  tree=$(value verified_tree)
  unchanged "$(git -C "$WORKTREE" rev-parse HEAD)"
  [ "$(git -C "$WORKTREE" write-tree)" = "$tree" ] || die 'Changes since verification; verify again'
  shift 3
  ATTACHMENTS=()
  for attachment in "$@"; do
    case "$attachment" in /*) ;; *) die 'Attachment paths must be absolute' ;; esac
    [ -f "$attachment" ] && [ ! -L "$attachment" ] || die 'Attachment must be a regular file'
    mime=$(file -b --mime-type "$attachment")
    case "$mime" in image/*|video/*) ;; *) die 'Attachment must be an image or video' ;; esac
    ATTACHMENTS+=(--attach "$attachment")
  done
  [ "$#" -le 50 ] || die 'At most 50 attachments are supported'
  if [ "$(json .pr.evidence)" = required ]; then [ "$#" -gt 0 ] || die 'Required evidence is missing'; fi
  if [ "$#" -gt 0 ]; then gh pr create --help | grep -q -- --attach || die 'Installed gh does not support --attach'; fi
  remote_matches
  pr_lookup
  cp "$body" "$RUN/pr-body.md"
  {
    printf '\n<!-- container-issue-pr: %s -->\n' "$(value branch)"
    printf '\nIssue: https://github.com/%s/issues/%s\n' "$REPOSITORY" "$(value issue)"
    printf '\nHost verification: `%s` (tree `%s`).\n' "$(value verified_at)" "$tree"
    printf '\n- [ ] Human verification completed\n'
    if [ "$(json .pr.evidence)" = waived ]; then printf '\nEvidence waiver: %s\n' "$(json .pr.waiver_reason)"; fi
  } >> "$RUN/pr-body.md"
  if [ "$(value phase)" = verified ]; then
    [ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$(value base_commit)" ] || die 'Commit history changed since verification'
    git -C "$WORKTREE" diff --cached --quiet && die 'No changes to publish'
    git -C "$WORKTREE" commit -m "$title"
    record code_commit "$(git -C "$WORKTREE" rev-parse HEAD)"
    phase committed
  fi
  commit=$(value code_commit)
  clean "$WORKTREE"
  [ "$(git -C "$WORKTREE" rev-parse HEAD)" = "$commit" ] || die 'HEAD changed after commit'
  [ "$(git -C "$WORKTREE" rev-parse HEAD^{tree})" = "$tree" ] || die 'Commit hooks changed the verified content'
  git -C "$WORKTREE" push -u "$(json .remote)" "HEAD:refs/heads/$(value branch)"
  phase publishing
  rc=0
  (cd "$WORKTREE" && gh pr create --repo "$REPOSITORY" --draft --base "$(json .base)" --head "$(value branch)" \
    --title "$title" --body-file "$RUN/pr-body.md" "${ATTACHMENTS[@]}") > "$RUN/pr-create.out" 2> "$RUN/pr-create.err" || rc=$?
  cat "$RUN/pr-create.out"
  gh pr list --repo "$REPOSITORY" --state all --head "$(value branch)" --base "$(json .base)" --json url > "$RUN/published-pr.json"
  [ "$(jq length "$RUN/published-pr.json")" = 1 ] || die 'Publication uncertain; inspect remote state before retrying'
  record pr_url "$(jq -r '.[0].url' "$RUN/published-pr.json")"
  gh pr view "$(value pr_url)" --repo "$REPOSITORY" --json url,state,isDraft,body,headRefOid,headRefName,baseRefName > "$RUN/pr.json"
  [ "$rc" = 0 ] || die 'PR may be partially published; reconcile body/attachments on the recorded URL'
  jq -e --arg base "$(json .base)" --arg branch "$(value branch)" --arg commit "$commit" \
    '.isDraft and .state == "OPEN" and .baseRefName == $base and .headRefName == $branch and .headRefOid == $commit and (.body | contains("- [ ] Human verification completed"))' "$RUN/pr.json" >/dev/null || die 'Published PR does not match verified draft'
  phase pr-created
  note 'Inspect the recorded PR body and every uploaded attachment before handoff.'
}

batch() {
  local config limit run pid failed=0
  config=$1; shift
  validate_config "$config"
  limit=$(jq -r .parallelism "$config")
  PIDS=()
  for run in "$@"; do
    cmp -s "$config" "$run/config.json" || die 'Batch tasks must use the same frozen config'
  done
  BATCH_ACTIVE=1
  for run in "$@"; do
    bash "$SCRIPT_DIR/workflow.sh" work "$run" &
    PIDS+=("$!")
    if [ "${#PIDS[@]}" -ge "$limit" ]; then
      for pid in "${PIDS[@]}"; do wait "$pid" || failed=1; done
      PIDS=()
    fi
  done
  for pid in "${PIDS[@]}"; do wait "$pid" || failed=1; done
  BATCH_ACTIVE=0
  return "$failed"
}

usage() {
  cat <<'USAGE'
workflow.sh prepare CONFIG ISSUE       # fetch Issue and establish immutable base
workflow.sh work RUN                   # after writing reviewed RUN/task.md
workflow.sh work-batch CONFIG RUN...   # bounded independent container jobs
workflow.sh collect RUN                # create host worktree via gtr; apply patch
workflow.sh verify RUN                 # host commands under resource locks
workflow.sh publish RUN TITLE BODY [ABS_MEDIA...]
workflow.sh status RUN                 # state and retained paths
Containers, worktrees and task artifacts are retained for inspection/recovery.
USAGE
}
for dependency in git jq rsync; do need "$dependency"; done
case "${1:-help}" in
  prepare) [ "$#" = 3 ] || die 'prepare CONFIG ISSUE'; need gh; prepare "$2" "$3" ;;
  work) [ "$#" = 2 ] || die 'work RUN'; work "$2" ;;
  work-batch) [ "$#" -ge 3 ] || die 'work-batch CONFIG RUN...'; shift; batch "$@" ;;
  collect) [ "$#" = 2 ] || die 'collect RUN'; collect "$2" ;;
  verify) [ "$#" = 2 ] || die 'verify RUN'; verify "$2" ;;
  publish) [ "$#" -ge 4 ] || die 'publish RUN TITLE BODY [ABS_MEDIA...]'; need gh; need file; shift; publish "$@" ;;
  status) [ "$#" = 2 ] || die 'status RUN'; cat "$2/state.json" ;;
  help|--help|-h) usage ;;
  *) usage; exit 1 ;;
esac
