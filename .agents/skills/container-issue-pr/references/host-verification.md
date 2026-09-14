# Host acceptance by technology

Choose commands from the target repository's manifests and instructions. Record
toolchain versions, tested commit/tree, commands, expected results and actual
results. Keep output/media under `CIP_RUN_DIR` so they do not enter the patch.
`CIP_WORKTREE` identifies the host worktree. A project-specific host script may
read device/session/port values from `host.env`.

| Technology | Host checks to configure |
| --- | --- |
| Flutter | Resolve dependencies on the host, format/analyze/test, then build and launch on the assigned Simulator/emulator. Operate the changed flow using available automation, assert final state and capture media. Use separate runtime/session/output paths. |
| Web | Install from the lockfile, run the repository's checks, build/start on an assigned port, exercise the changed flow in a host browser and inspect responsive/UI state. Stop the server before releasing its port lock. |
| Backend | Resolve dependencies and run unit/integration checks against isolated test data/services. Exercise the changed API or worker behavior from the host; record observable responses/state. Shared databases and ports require their own locks. |
| Swift/iOS | Use the host's Xcode/toolchain and the repository's project generator if applicable. Build/test on the assigned Simulator, launch and exercise the changed flow, inspect state and capture media. macOS/Xcode verification occurs on the host even when editing runs in Linux. |
| Kotlin/Android | Use the host JDK/Android SDK and repository Gradle wrapper. Run tests, build/install on the assigned emulator/device, exercise the changed flow, inspect state and capture media. |

Each acceptance script must remain in the foreground until launch, operations,
capture and shutdown have finished. Use process handles to stop only the processes
it starts, including on error; returning while a background server/device session
still owns a resource breaks lock ownership. Avoid automatic retries of UI input.

When host acceptance finds a defect, fix it in the assigned host worktree or start
an explicitly reviewed new container iteration. Review/stage the resulting changes
and rerun affected acceptance before publishing. A failing check or unavailable
required device leaves the task incomplete; do not replace it with a successful
container test result.
