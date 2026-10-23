#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
export DART_SUPPRESS_ANALYTICS=true

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Workspace quality checks require the supported macOS host.' >&2
  exit 1
fi

# Missing encoders must fail the hook instead of silently skipping real MP4 tests.
for tool in ffmpeg ffprobe; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing $tool. Install ffmpeg before committing (brew install ffmpeg)." >&2
    exit 1
  fi
  "$tool" -version >/dev/null
done

flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed \
  bin lib test tool integration_test \
  packages/marionette_agent_util/lib packages/marionette_agent_util/test \
  packages/marionette_agent_util/flutter_test example/lib example/test
dart analyze
dart run tool/check_release.dart
dart run tool/license_notices.dart --check
dart test --concurrency=1 --timeout=2m
(
  cd packages/marionette_agent_util
  dart test --concurrency=1
  flutter test flutter_test
)
(
  cd example
  flutter test
)
dart run integration_test/release_smoke.dart
