#!/usr/bin/env bash
set -euo pipefail

# SDK tools inspect their own Git checkout, independently of the calling hook.
while IFS= read -r quality_git_variable; do
  unset "$quality_git_variable"
done < <(git rev-parse --local-env-vars)

exec "$@"
