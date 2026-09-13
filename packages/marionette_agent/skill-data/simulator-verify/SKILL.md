---
name: simulator-verify
description: Verify Flutter app behavior on iOS Simulator through marionette-agent and capture screenshots or recordings. Use for runtime acceptance checks, CLI changes, and reproducible evidence.
---

# Simulator Verify

Operate the debug app through the CLI under test, then compare its response with
the actual screen and state. This is runtime acceptance verification alongside
automated tests. This distributable guide adapts the repository's simulator-verify
workflow for installed CLI users as well as repository development.

## Prepare an exclusive run

1. Read `marionette-agent skills get core` and the task's acceptance conditions.
   Record the app revision, CLI revision or version, and local changes. For this
   repository, use its `example/` fixture; setup and controls are described in
   [references/example.md](references/example.md).
2. List available devices and select an unused iOS Simulator UDID. Record the
   UDID, task/worker, runtime, session, runner, bundle ID, and ownership state in
   the host's shared allocation record. Keep the complete boot/install/operate/
   capture/cleanup interval exclusive. A CLI runtime lock does not reserve a device.
   Confirm the previous owner's cleanup before accepting a reassigned device.
3. Create a short private run directory (mode 0700), with separate private logs
   and shareable evidence. Set `MARIONETTE_AGENT_RUNTIME_DIR` to a new directory
   inside it on every CLI call; its absolute path must fit within 80 UTF-8 bytes.
   Use a distinct session and evidence directory. See the preparation example in
   [references/example.md](references/example.md).
4. Launch the assigned app in debug mode, saving its VM Service URI with
   `--vmservice-out-file`. Keep the runner alive in a separate terminal and record
   its process ownership. Raw runner logs and URI files remain private.

## Operate and capture

Use the CLI built from the task's checkout for CLI development. Installed CLI
users can invoke `marionette-agent` directly. Keep URI loading out of shell traces.

1. Connect the chosen session with the URI from the private file. Observe initial
   state with `snapshot` and capture a baseline screenshot to a new path.
2. Execute the operation once and record exit code plus text/JSON response. For
   refs, use the latest actual snapshot; selectors must identify a unique target.
3. Take another snapshot and screenshot. Compare both with the expected state.
   For error scenarios, check the error and absence of unintended app changes.
   An `unknown` operation outcome requires observation before any further action.
4. For transitions or gestures, use the CLI's `record start <new-path.mp4>
   --platform ios --device <UDID>` and `record stop`. If recording itself fails,
   record that acceptance gap and use available Simulator capture for diagnosis.
5. Open every selected image; play videos or inspect chronological frames.
   A nonempty file is insufficient. Add sanitized CLI text/JSON when media alone
   cannot show the behavior, such as errors, logs, or the `skills` command.

After code changes, stop the old run's session/daemon and use a fresh runtime so
the next run executes the new code.

## Clean up and hand off

Stop your recording, close your session, and confirm the owned daemon stopped.
Quit your Flutter runner to stop the app; detach alone is insufficient. If already
detached, terminate only your bundle ID on the assigned UDID. Confirm the runner,
app, and recording are stopped before marking the allocation released. Remove
private URI files when no longer needed and retain selected evidence for handoff.
For an interrupted worker, verify ownership of each resource before reclaiming it;
an unknown ownership state cannot be reassigned based only on elapsed time.

Return acceptance conditions, actual CLI commands/results, Flutter/binding and CLI
versions, Simulator model/OS/UDID, evidence paths with observed behavior, and steps
to reset, relaunch, reacquire the URI, and reproduce. Record human verification as
pending. A blocked launch, inconsistent observation, or untested required scenario
leaves verification incomplete with its concrete reason.

Load the supplementary example setup with
`marionette-agent skills get simulator-verify --full`, or locate it using
`marionette-agent skills path simulator-verify`.
