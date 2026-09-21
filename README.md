# marionette-agent

Flutter app automation for AI agents. Observe the UI, act on a target, and verify the result through a Dart CLI or a stdio MCP server.

[English documentation](https://r0227n.github.io/marionette_agent/en/) · [日本語ドキュメント](https://r0227n.github.io/marionette_agent/ja/) · [Detailed references](docs/README.md)

The current development version runs on **macOS** and connects to **debug Flutter apps with Marionette enabled**. It supports named sessions, snapshot refs, text input, gestures, screenshots, recordings, and sequential workflows. Apps can run in iOS Simulator, Android Emulator, macOS, Chrome, or Flutter tester, subject to the selected platform’s requirements.

The documentation site is deployed from `develop`. Until the first deployment completes, use the [English source](website/src/content/docs/en/getting-started/overview.md), [Japanese source](website/src/content/docs/ja/getting-started/overview.md), or [local preview](website/README.md).

## Installation

Install from a local checkout. You need Flutter and Dart **3.13.2 or newer, below 4.0.0**. The example pins Flutter 3.47.2; platform SDKs such as Xcode are needed for the corresponding app runtime.

```sh
git clone --branch develop https://github.com/r0227n/marionette_agent.git
cd marionette_agent/packages/marionette_agent
flutter pub get
mkdir -p "$HOME/.local/bin"
dart run bin/marionette_agent.dart install "$HOME/.local/bin" --timeout 120000
export PATH="$HOME/.local/bin:$PATH"
marionette-agent --version
```

Add the PATH export to your shell configuration to keep it across terminals. `install` creates the executable and an adjacent `.marionette-agent-*` Skills bundle; keep them together if you move the installation. It requires an existing destination directory and refuses to overwrite an existing executable.

To run directly from the CLI package after resolving dependencies:

```sh
dart run bin/marionette_agent.dart --help
```

To update, check out the desired revision, refresh its dependencies, and run this from the repository root:

```sh
marionette-agent upgrade --source packages/marionette_agent   "$HOME/.local/bin" --timeout 120000
```

`upgrade` compiles the local source before replacing the executable. It does not download source updates or update Flutter.

## Quick start

Start a Marionette-enabled debug app and obtain its VM Service URI. The [first interaction guide](https://r0227n.github.io/marionette_agent/en/getting-started/quick-start/) shows how to start the bundled example in iOS Simulator. Keep that runner open and set `VM_URI` to the URI it produced in a second terminal.

Run the following against the example’s Controls screen:

```sh
export MARIONETTE_AGENT_SESSION=demo
marionette-agent connect "$VM_URI"
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

Verify that the tap count increased and the input displays `hello`. Open the screenshot at the returned path. Closing this connection leaves an externally started app running; stop its Flutter runner separately.

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

## Development and documentation

| Location | Purpose |
| --- | --- |
| [packages/marionette_agent](packages/marionette_agent/) | CLI, daemon, MCP server, and tests |
| [packages/marionette_agent_util](packages/marionette_agent_util/) | Optional app providers and runtime helpers |
| [example](example/README.md) | Flutter app for reproducible verification |
| [website](website/README.md) | Starlight site, built and verified with Bun |
| [docs](docs/README.md) | English supplements and internal design documents |
| [docs/ja](docs/ja/README.md) | Japanese supplements |

English is the primary public language; Japanese is maintained alongside it. Update paired pages in the same PR using the [documentation policy](docs/documentation.md). The website owns user guides; repository supplements cover details beyond those guides.

Read [AGENTS.md](AGENTS.md) before making changes. CLI changes require formatting, analysis, relevant tests, and the full test suite at handoff; behavior changes also require verification against the example in iOS Simulator. The [product contract](docs/SPEC.md) and [architecture](docs/ARCHITECTURE.md) currently contain internal Japanese documentation.

For website development and the GitHub Pages deployment pipeline, follow [website/README.md](website/README.md).
