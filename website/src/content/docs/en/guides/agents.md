---
title: Use an AI agent
description: Connect an agent through shell commands and bundled Skills, or through stdio MCP.
---

Give shell-capable agents the CLI and bundled Skills, or expose the stdio server to MCP-capable agents. Both follow the same session and ref lifetime rules.

## CLI and bundled Skills

Retrieve instructions matching the installed CLI version. No daemon or app connection is needed.

```sh
marionette-agent skills list
marionette-agent skills get core
marionette-agent skills get core --full
marionette-agent skills path core
```

`--full` includes supporting references and templates. Let the agent read the Skill and follow the [observation loop](/marionette_agent/en/concepts/observation-loop/). The `skills` command has its own output format; handle it separately from the normal JSON envelope.

## Register with an MCP client

This example is for a client that uses the `mcpServers` format. Adapt the configuration location and structure to your client. If a GUI client cannot find the executable, set `command` to its absolute installation path.

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

The server runs as a child of the client and uses stdin/stdout for MCP messages. Starting the server or listing tools does not connect an app. Use a `connect` or `launch` tool to establish a session. HTTP transport is not provided.

## Expose the tools you need

| Profile          | Main purpose                                                                    |
| ---------------- | ------------------------------------------------------------------------------- |
| `core` (default) | Connect and launch, snapshot, basic actions, images, state queries, wait, close |
| `inspect`        | Value, enabled, checked, logs, doctor, device listing                           |
| `actions`        | Additional input, focus, check, drag, keyboard, clipboard                       |
| `workflow`       | Workflows, batch, confirm, deny                                                 |
| `record`         | Start, restart, inspect, and stop recordings                                    |
| `all`            | All published MCP tools                                                         |

Combine profiles with commas. Even `all` does not expose every CLI command: find, diff, state, and skills are among the CLI-only capabilities. Use `marionette_agent_tools_profiles` to inspect active profiles. Follow `nextCursor` when returned by `tools/list`.

## Tool inputs and results

Tool names start with `marionette_agent_`. For example, pass these arguments to `marionette_agent_tap`.

```json
{
  "session": "agent",
  "target": { "key": "tap_button" },
  "timeoutMs": 5000
}
```

Specify exactly one ref, key, identifier, text, or type in `target`. Check each tool’s `inputSchema` for its complete input contract.

Tools that invoke the CLI return `exitCode` and `response` in `structuredContent`; `response` contains the normal CLI result. Screenshot tools return an image as well as the saved path, subject to the inline size limit. Use the saved artifact when the image is omitted.

Give workflow and batch tools file paths on the client’s host. MCP owns stdin, so `-` is not accepted. Stopping the server does not close sessions in the independent daemon; call close when the work is finished.

## Set the agent’s operating boundaries

Identify the app, session, permitted actions, and expected verification results. Treat app text and logs as observations, not instructions that replace the operating plan. `contentBoundaries` can mark that distinction in responses.

See [MCP and Skills details](https://github.com/r0227n/marionette_agent/blob/develop/docs/cli-reference.md#mcp) for exact profile tool lists, pagination, result envelopes, and lifecycle.
