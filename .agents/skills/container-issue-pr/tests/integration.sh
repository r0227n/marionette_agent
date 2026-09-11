#!/usr/bin/env bash
# Host-run integration tests with real Docker, Git, gtr, rsync and patch semantics.
# Usage: bash tests/integration.sh <image>
set -eo pipefail
TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SKILL_DIR=$(cd "$TEST_DIR/.." && pwd -P)
HELPER="$SKILL_DIR/scripts/workflow.sh"
IMAGE=${1:?Supply the built agent image}
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/cip-integration.XXXXXX")
FIXTURE=$(cd "$FIXTURE" && pwd -P)
export CIP_FIXTURE_ROOT="$FIXTURE"
export CIP_FIXTURE_GIT=$(command -v git)
export PATH="$TEST_DIR/fixtures:$PATH"
SOURCE="$FIXTURE/source with spaces"
CONFIG="$FIXTURE/config.json"
mkdir -p "$SOURCE" "$FIXTURE/state" "$FIXTURE/locks"
trap 'printf "Fixture and evidence retained: %s\n" "$FIXTURE"' EXIT
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_failure() { if "$@" > "$FIXTURE/expected-error.log" 2>&1; then fail "Unexpected success: $*"; fi; }
state() { jq -r .phase "$1/state.json"; }
run_path() { printf '%s/state/fixture-project-issue-%s\n' "$FIXTURE" "$1"; }

git init -q --initial-branch=main "$SOURCE"
git -C "$SOURCE" config user.name 'Workflow fixture'
git -C "$SOURCE" config user.email fixture@localhost
git -C "$SOURCE" config core.hooksPath /dev/null
git -C "$SOURCE" config gtr.worktrees.dir "$FIXTURE/worktrees"
git init -q --bare "$FIXTURE/remote.git"
git -C "$SOURCE" remote add origin https://github.com/fixture/project.git
# The fixture Git wrapper redirects only fetch/push to the local bare remote.
printf 'original\n' > "$SOURCE/message.txt"
printf 'rename\n' > "$SOURCE/rename-from.txt"
printf 'delete\n' > "$SOURCE/delete.txt"
printf 'host-only\n' > "$SOURCE/.env"
printf '#!/bin/bash\ntrue\n' > "$SOURCE/executable.sh"
printf 'local.extra\n' > "$SOURCE/.gitignore"
printf 'extra context\n' > "$SOURCE/local.extra"
cat > "$SOURCE/agent.sh" <<'AGENT'
#!/usr/bin/env bash
set -e
mode=$(cat)
[ "$mode" != fail ] || exit 42
[ ! -e .env ]
[ "$(cat local.extra)" = 'extra context' ]
[ -f .git ]  # gtr linked worktree, not a copied host .git directory
printf 'updated\n' > message.txt
mv rename-from.txt rename-to.txt
rm delete.txt
printf '\000\001\377' > binary.dat
chmod +x executable.sh
ln -s message.txt relative-link
git add -A
git -c user.name=Fixture -c user.email=fixture@localhost commit -qm 'Agent fixture commit'
printf 'Agent worktree: %s\n' "$PWD"
AGENT
cat > "$SOURCE/host-check.sh" <<'HOST'
#!/usr/bin/env bash
set -e
[ ! -e /.dockerenv ]
[ "$CIP_WORKTREE" = "$(pwd -P)" ]
[ "$(cat message.txt)" = updated ]
[ "$(cat rename-to.txt)" = rename ]
[ ! -e delete.txt ]
[ -x executable.sh ]
[ -L relative-link ]
[ "$(cat relative-link)" = updated ]
[ "$(cat .env)" = host-only ]
[ "$(od -An -tx1 binary.dat | tr -d ' \n')" = 0001ff ]
printf 'Host acceptance passed on %s\n' "$(uname -s)"
HOST
git -C "$SOURCE" add -A
git -C "$SOURCE" add -f .env
git -C "$SOURCE" commit -qm 'Fixture baseline'
git -C "$SOURCE" push -qu origin main
jq --arg src "$SOURCE" --arg state "$FIXTURE/state" --arg locks "$FIXTURE/locks" --arg image "$IMAGE" \
  '.source=$src | .state_root=$state | .lock_root=$locks | .repository="fixture/project" | .base="main" |
   .container.image=$image | .container.network="none" | .agent.argv=["bash","agent.sh"] |
   .copy.extra=["local.extra"] | .host.resources=["fixture-device"] |
   .host.commands=[{name:"Host acceptance",cwd:".",argv:["bash","host-check.sh"]}] |
   .pr.evidence="waived" | .pr.waiver_reason="Fixture tests assert file bytes, Git refs and exit status."' \
  "$SKILL_DIR/assets/config.example.json" > "$CONFIG"

printf 'dirty\n' >> "$SOURCE/message.txt"
expect_failure bash "$HELPER" prepare "$CONFIG" 90
git -C "$SOURCE" restore message.txt
pass 'dirty source rejected without copying'
CIP_FIXTURE_ISSUE_STATE=closed expect_failure bash "$HELPER" prepare "$CONFIG" 91
[ "$(jq -r .state "$(run_path 91)/issue.json")" = closed ] || fail 'closed Issue was not fetched'
pass 'closed Issue rejected'

for number in 1 2 3; do
  bash "$HELPER" prepare "$CONFIG" "$number" > "$FIXTURE/prepare-$number.out"
  printf 'change\n' > "$(run_path "$number")/task.md"
done
printf 'fail\n' > "$(run_path 3)/task.md"
expect_failure bash "$HELPER" work-batch "$CONFIG" "$(run_path 1)" "$(run_path 2)" "$(run_path 3)"
[ "$(state "$(run_path 1)")" = result-ready ] || { cat "$FIXTURE/expected-error.log"; fail 'first result'; }
[ "$(state "$(run_path 2)")" = result-ready ] || fail 'second result'
[ "$(state "$(run_path 3)")" = agent-failed ] || fail 'failed agent status'
pass 'parallel container agents isolated; failed job reported without discarding successes'
[ "$(cat "$SOURCE/message.txt")" = original ] || fail 'source was modified'
[ ! -e "$(run_path 1)/input/.git" ] && [ ! -e "$(run_path 1)/input/.env" ] || fail 'copy exclusions'
pass 'host snapshot excludes Git metadata/dotenv; original source preserved'

RUN=$(run_path 1)
bash "$HELPER" collect "$RUN" > "$FIXTURE/collect.out"
WORKTREE=$(jq -r .host_worktree "$RUN/state.json")
[ -f "$WORKTREE/.git" ] || fail 'host gtr worktree missing'
[ "$(cat "$WORKTREE/.env")" = host-only ] || fail 'excluded file was deleted'
pass 'host gtr worktree receives binary, executable, symlink, rename and deletion changes'

mkdir "$FIXTURE/locks/fixture-device.lock"
expect_failure bash "$HELPER" verify "$RUN"
[ "$(state "$RUN")" = collected ] && [ ! -e "$RUN/verification.log" ] || fail 'busy lock started verification'
rmdir "$FIXTURE/locks/fixture-device.lock"
pass 'busy device lock blocks all host commands'
bash "$HELPER" verify "$RUN"
[ "$(state "$RUN")" = verified ] && [ ! -e "$FIXTURE/locks/fixture-device.lock" ] || fail 'verification/lock release'
pass 'host acceptance succeeds and releases its device lock'

printf '## Summary\nFixture integration.\n' > "$FIXTURE/body.md"
printf 'changed after verification\n' > "$WORKTREE/message.txt"
git -C "$WORKTREE" add message.txt
expect_failure bash "$HELPER" publish "$RUN" 'Fixture change' "$FIXTURE/body.md"
[ ! -e "$FIXTURE/pr.json" ] || fail 'stale verification published'
expect_failure bash "$HELPER" verify "$RUN"
[ "$(state "$RUN")" = verification-failed ] || fail 'host failure not recorded'
pass 'stale verification and failed host acceptance prevent publication'
printf 'updated\n' > "$WORKTREE/message.txt"
git -C "$WORKTREE" add message.txt
bash "$HELPER" verify "$RUN"
bash "$HELPER" publish "$RUN" 'Fixture change' "$FIXTURE/body.md"
[ "$(state "$RUN")" = pr-created ] || fail 'publication state'
[ "$(git -C "$FIXTURE/remote.git" rev-parse refs/heads/feature/issue-1)" = "$(jq -r .code_commit "$RUN/state.json")" ] || fail 'pushed commit mismatch'
pass 'verified commit pushed to local remote; draft PR contract checked through gh fixture'
expect_failure bash "$HELPER" publish "$RUN" 'Duplicate' "$FIXTURE/body.md"
pass 'completed task cannot publish a duplicate'

OTHER=$(run_path 2)
git -C "$SOURCE" gtr new feature/issue-2 --from main --no-fetch --no-copy --no-hooks --porcelain > "$FIXTURE/conflict-gtr.tsv"
OTHER_TREE=$(awk -F '\t' '$1=="path" {print $2}' "$FIXTURE/conflict-gtr.tsv")
printf 'someone else\n' > "$OTHER_TREE/message.txt"
expect_failure bash "$HELPER" collect "$OTHER"
[ "$(cat "$OTHER_TREE/message.txt")" = 'someone else' ] || fail 'existing work overwritten'
pass 'existing host worktree changes are preserved on collection failure'
printf 'All integration scenarios passed. GitHub and model calls were simulated.\n'
