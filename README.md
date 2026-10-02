# marionette-agent

Flutter app automation for AI agents. Observe the UI, act on a target, and verify the result through a Dart CLI or a stdio MCP server.

[English documentation](https://r0227n.github.io/marionette_agent/en/) · [日本語ドキュメント](https://r0227n.github.io/marionette_agent/ja/) · [Detailed references](docs/README.md)

Version 1.0.1 runs on **macOS** and connects to **debug Flutter apps with Marionette enabled**. It supports named sessions, snapshot refs, text input, gestures, screenshots, recordings, and sequential workflows. Apps can run in iOS Simulator, Android Emulator, macOS, Chrome, or Flutter tester, subject to the selected platform’s requirements.

The documentation site is deployed from `develop`. For offline reading, use the [English source](website/src/content/docs/en/getting-started/overview.md), [Japanese source](website/src/content/docs/ja/getting-started/overview.md), or [local preview](website/README.md).

## Installation

Install 1.0.1 from the immutable Git tag and compile locally. GitHub Releases
provide the release notes and source archives; pub.dev publication is disabled.
The documentation site tracks development on `develop`, while this installation
uses the released source revision.

You need Flutter and Dart **3.13.2 or newer, below 4.0.0**. The example pins Flutter
3.47.2; platform SDKs such as Xcode are needed for the corresponding app runtime.

```sh
git clone --branch v1.0.1 https://github.com/r0227n/marionette_agent.git
cd marionette_agent
flutter pub get --enforce-lockfile
mkdir -p "$HOME/.local/bin"
dart run bin/marionette_agent.dart install "$HOME/.local/bin" --timeout 120000
export PATH="$HOME/.local/bin:$PATH"
marionette-agent --version
```

Expected version: `1.0.1`.

Add the PATH export to your shell configuration to keep it across terminals. `install` creates the executable and an adjacent `.marionette-agent-*` Skills and license notices bundle; keep them together if you move the installation. It requires an existing destination directory and refuses to overwrite an existing executable.

The repository root is the CLI package and Pub workspace root. One `flutter pub get` resolves the CLI, `packages/marionette_agent_util`, and `example` into the root lockfile.

To run directly from the repository root after resolving dependencies:

```sh
dart run bin/marionette_agent.dart --help
```

To update, check out the desired revision, refresh its dependencies, and run this from the repository root:

```sh
marionette-agent upgrade --source . "$HOME/.local/bin" --timeout 120000
```

`upgrade` compiles the local source before replacing the executable. It does not download source updates or update Flutter.

## Quick start

From the repository root, launch the bundled example with Flutter tester. This
needs no Simulator or Xcode and is the shortest reproducible first interaction.
`launch` starts the debug app, obtains its authenticated VM Service URI, and connects
without asking you to copy credentials. It owns the runner until `close`.

```sh
export MARIONETTE_AGENT_SESSION=demo
marionette-agent --timeout 180000 launch ./example --platform tester
marionette-agent snapshot
marionette-agent tap --key tap_button
marionette-agent get text --key tap_result
marionette-agent snapshot
marionette-agent fill --key text_input 'hello'
marionette-agent snapshot
marionette-agent screenshot
marionette-agent close
unset MARIONETTE_AGENT_SESSION
```

Verify `Tap count: 1` and `5 characters`, then open the returned screenshot and
confirm the input displays `hello`. Flutter tester covers shared Flutter UI;
native plugins and OS behavior need the corresponding target platform.

For an externally started Marionette-enabled debug app, obtain its authenticated
VM Service URI in a private file and use `marionette-agent connect "$VM_URI"`
instead of `launch`. Closing that connection leaves the app running; stop its
Flutter runner separately. For your own app, the minimum setup is:

```sh
flutter pub add marionette_flutter:0.6.0
```

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const MyApp()); // Your existing root widget.
}
```

Use unique `ValueKey` targets and debug builds. Keep VM Service tokens private and
endpoints on loopback or a trusted tunnel; use test data. See [SECURITY.md](SECURITY.md)
for the public Issues reporting route and safe use conditions. Never post secrets,
personal information, authentication tokens, or abuse-enabling details.

Snapshots also return short refs such as `@e7`. Use only refs returned by the latest snapshot in the selected session. A new snapshot, a UI mutation, or reconnection expires earlier refs. Reobserve after each action; the CLI does not automatically resend UI operations.

For your own app, follow [app integration](https://r0227n.github.io/marionette_agent/en/getting-started/app-integration/). Optional app-side providers add typed input state, semantic find operations, and mapped screenshots.

## Commands

| Task | Commands |
| --- | --- |
| Connect and manage sessions | `connect`, `launch`, `session list`, `session show`, `close` |
| Observe | `snapshot`, `get text/box/count/value`, `is visible/enabled/checked`, `logs` |
| Interact | `tap`, `fill`, `type`, `swipe`, `scroll`, `find`, `wait` |
| Capture and compare | `screenshot`, `record start/status/stop/restart`, `diff snapshot/screenshot` |
| Automate | `workflow schema/validate/run`, `batch`, `confirm`, `deny` |
| Diagnose and integrate | `doctor`, `device list`, `skills`, `mcp` |

See the [command reference](https://r0227n.github.io/marionette_agent/en/reference/commands/) for complete syntax and capability requirements. Use `--json` for structured results, `--session NAME` for isolation, and `--timeout MS` for a deadline that includes queue time.

```sh
marionette-agent --session demo snapshot --json
marionette-agent workflow schema --json
marionette-agent doctor --json
```

Check both the error `code` and `outcome`. An `unknown` outcome means an operation may have reached the app; inspect the current state before deciding what to do next.

## Use with agents

Retrieve the instructions bundled with your installed CLI:

```sh
marionette-agent skills get core
marionette-agent skills get simulator-verify --full
```

For an MCP client that accepts `mcpServers`, configure the executable on its PATH:

```json
{
  "mcpServers": {
    "marionette-agent": {
      "command": "marionette-agent",
      "args": ["--session", "agent", "mcp", "--tools", "core,inspect"]
    }
  }
}
```

The MCP server uses stdio. Choose additional tool profiles when needed; the [agent guide](https://r0227n.github.io/marionette_agent/en/guides/agents/) and [integration details](docs/cli-reference.md#mcp) describe the available profiles and result contracts.

## Headless apps and recordings

`launch` manages the selected app runtime and connects the session. Prepare the example’s dependencies before running this from the repository root:

```sh
marionette-agent --session headless --timeout 600000 launch ./example --platform tester
marionette-agent --session headless snapshot
marionette-agent --session headless screenshot
marionette-agent --session headless --timeout 60000 close
```

Flutter tester is useful for shared Flutter UI; verify native plugins and OS behavior on the relevant platform. A session created by `launch` owns its runner, so `close` also shuts down that app. See [headless execution](https://r0227n.github.io/marionette_agent/en/guides/headless/) for platform options and [capture](https://r0227n.github.io/marionette_agent/en/guides/capture/) for Flutter rendering versus device recordings. Flutter rendering recordings require ffmpeg and capture a single Flutter view without audio.

## Support, troubleshooting, and removal

The supported CLI host is macOS. The verification baseline is Flutter 3.47.2 /
Dart 3.13.2 on macOS arm64; other SDKs satisfying the constraint are not an
exhaustive compatibility promise. iOS Simulator needs Xcode, Android needs its
SDK/adb, and Chrome/macOS launch needs the corresponding runtime. Linux/Windows
host support and iOS device recording are not promised. Recordings need platform
permissions or ffmpeg depending on the backend; none is needed for the quick start.

- Compilation fails: confirm Flutter/Dart are on PATH and resolve the committed
  lockfile at the repository root. Increase install timeout for a slow machine.
- Existing executable: use `upgrade --source .` from the desired checkout.
- Missing target or stale ref: take a new snapshot and check the unique key.
- Missing capabilities: use the fixed `marionette_flutter: 0.6.0`; optional util
  providers must come from the same release checkout. Read the
  [1.x compatibility policy](website/src/content/docs/en/reference/compatibility.md).
- Failed checks or connection: run `marionette-agent doctor --json`; include
  redacted output, versions, host, and target runtime in a
  [support issue](https://github.com/r0227n/marionette_agent/issues).

To uninstall, close your sessions/recordings and stop externally started runners.
Remove the executable you installed and its matching `.marionette-agent-*`
directory after checking the path; upgrades retain old bundles, which you can
remove once no executable uses them. Remove your PATH entry if no longer needed.
Do not delete other users' runtime or capture files. Latest 1.x will receive
best-effort fixes after release; there is no support SLA.

## License and release

Original material is Apache-2.0: [LICENSE](LICENSE) and [NOTICE](NOTICE).
[Third-party notices](THIRD_PARTY_NOTICES.txt) retain dependency licenses and
copyrights and are installed alongside the binary. Development skills have a
separate [MIT notice](third_party/mattpocock-skills-LICENSE). See the
[release checklist](docs/releasing.md) for distribution scope and final gates.

## Development and documentation

| Location | Purpose |
| --- | --- |
| [Repository root](pubspec.yaml) | CLI, daemon, MCP server, and tests |
| [packages/marionette_agent_util](packages/marionette_agent_util/) | Optional app providers and runtime helpers |
| [samples/workflows](samples/workflows/README.md) | CLI workflow and input samples |
| [example](example/README.md) | Flutter app for reproducible verification |
| [website](website/README.md) | Starlight site, built and verified with Bun |
| [docs](docs/README.md) | English supplements and internal design documents |
| [docs/ja](docs/ja/README.md) | Japanese supplements |

English is the primary public language; Japanese is maintained alongside it. Update paired pages in the same PR using the [documentation policy](docs/documentation.md). The website owns user guides; repository supplements cover details beyond those guides.

Read [AGENTS.md](AGENTS.md) before making changes. CLI changes require formatting, analysis, relevant tests, and the full test suite at handoff; behavior changes also require verification against the example in iOS Simulator. The [product contract](docs/SPEC.md) and [architecture](docs/ARCHITECTURE.md) are available in English, with [Japanese specification](docs/ja/SPEC.ja.md) and [Japanese architecture](docs/ja/ARCHITECTURE.ja.md) counterparts.

For website development and the GitHub Pages deployment pipeline, follow [website/README.md](website/README.md).
