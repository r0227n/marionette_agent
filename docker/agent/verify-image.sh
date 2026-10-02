#!/usr/bin/env bash
# Run on the host. Copies actual project files, without Git metadata/host caches.
set -eo pipefail
SOURCE=${1:?Usage: verify-image.sh SOURCE [IMAGE] [OUTPUT_DIR]}
SOURCE=$(cd "$SOURCE" && pwd -P)
IMAGE=${2:-marionette-agent-dev:flutter-3.47.2}
OUTPUT=${3:-$(mktemp -d "${TMPDIR:-/tmp}/marionette-image-check.XXXXXX")}
mkdir -p "$OUTPUT/input"
OUTPUT=$(cd "$OUTPUT" && pwd -P)
CONTAINER="marionette-image-check-$$-${RANDOM}"
CREATED=0
finish() {
  local rc=$?
  if [ "$CREATED" = 1 ]; then docker stop -t 10 "$CONTAINER" >/dev/null || true; fi
  printf 'Container retained: %s\nEvidence: %s\n' "$CONTAINER" "$OUTPUT"
  exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker create --name "$CONTAINER" --label marionette-agent.verification=true \
  --init --entrypoint bash "$IMAGE" -c 'trap "exit 0" TERM INT; while :; do sleep 1 & wait "$!" || :; done' > "$OUTPUT/container.id"
CREATED=1
docker start "$CONTAINER" >/dev/null
docker exec "$CONTAINER" bash -c '
  set -e
  id
  flutter --version
  dart --version
  git gtr --version
  codex --version
  codex exec --dangerously-bypass-approvals-and-sandbox --help >/dev/null
  mkdir /tmp/project
  git -C /tmp/project init -q
  git -C /tmp/project -c user.name=Check -c user.email=check@localhost commit -qm seed --allow-empty
  git -C /tmp/project gtr new feature/image-check --from HEAD --track none --no-copy --no-hooks --no-fetch --porcelain
' > "$OUTPUT/environment.log" 2>&1
WORKTREE=$(awk -F '\t' '$1=="path" {print $2}' "$OUTPUT/environment.log")
case "$WORKTREE" in /tmp/*) ;; *) printf 'No container gtr worktree\n' >&2; exit 1 ;; esac
rsync -rlpt --exclude=.git --exclude=.dart_tool --exclude=build --exclude=Pods \
  --exclude=.flutter-plugins-dependencies --exclude=.env --exclude='.env.*' \
  "$SOURCE/packages" "$SOURCE/example" "$OUTPUT/input/"
docker cp "$OUTPUT/input/." "$CONTAINER:$WORKTREE/"
docker exec -u 0 "$CONTAINER" chown -R 10001:10001 "$WORKTREE"
docker exec -w "$WORKTREE" "$CONTAINER" bash -c '
  set -e
  cd packages/marionette_agent
  dart pub get
  dart analyze
  # Runtime acceptance belongs to the macOS host. These tests exercise portable
  # command/model contracts; the full suite includes macOS-specific stat/tempdir
  # assumptions and is intentionally run on the host, not emulated here.
  dart test test/protocol_test.dart test/backend_test.dart test/snapshot_test.dart \
    test/feature_commands_test.dart test/swipe_test.dart test/workflow_model_test.dart
  cd ../marionette_agent_util
  dart pub get
  dart analyze
  dart test
  cd ../../example
  flutter pub get
  flutter analyze
  flutter test
' > "$OUTPUT/project-checks.log" 2>&1
printf 'PASS: project dependencies, analysis and tests in image\n'
cat "$OUTPUT/environment.log"
