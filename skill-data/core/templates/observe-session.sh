#!/usr/bin/env bash
# Run with MRA_VM_URI_FILE pointing to a private runner-generated URI file.
# Choose an unused MRA_SESSION and an existing private MRA_EVIDENCE_DIR.
set -euo pipefail
set +x
: "${MRA_VM_URI_FILE:?Set the private VM Service URI file}"
: "${MRA_EVIDENCE_DIR:?Set an existing evidence directory}"
: "${MRA_SESSION:?Set an unused session name}"
MRA_TEMPLATE_URI=$(cat "$MRA_VM_URI_FILE")
marionette-agent --session "$MRA_SESSION" connect "$MRA_TEMPLATE_URI"
unset MRA_TEMPLATE_URI
trap 'marionette-agent --session "$MRA_SESSION" close' EXIT
marionette-agent --session "$MRA_SESSION" snapshot
marionette-agent --session "$MRA_SESSION" screenshot "$MRA_EVIDENCE_DIR/observed.png"
