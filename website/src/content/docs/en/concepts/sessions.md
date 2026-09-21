---
title: Sessions and connection lifetime
description: Isolate connections and observations, and understand what connect and launch own.
---

A session holds a connection to one app and its observations. A local daemon maintains the connection between commands, so you can invoke the CLI one command at a time.

## Select a named session

Set `VM_URI` to the VM Service URI of a running app for this example.

```sh
marionette-agent --session demo connect "$VM_URI"
marionette-agent --session demo snapshot
marionette-agent --session demo session show
marionette-agent session list
```

Session names begin with a letter or digit and contain up to 64 letters, digits, underscores, or hyphens. The default is `default`. You can set a default with `MARIONETTE_AGENT_SESSION`.

Commands within a session run in order. Different sessions are independent, but two sessions cannot own the same normalized URI. Close a session before connecting it to a different URI.

## What connect and launch own

| Method    | Owned by the CLI                                        | Effect of close                                             |
| --------- | ------------------------------------------------------- | ----------------------------------------------------------- |
| `connect` | A connection to an already running app                  | Closes the connection; leaves the app running               |
| `launch`  | The launched app, execution environment, and connection | Finalizes recording and terminates the owned app and device |

This distinction determines cleanup scope. Do not use `close` expecting it to shut down a Simulator you started separately.

## Close a connection

```sh
marionette-agent --session demo close
```

Closing a missing session succeeds. To close every session, run without an explicit `--session`.

```sh
marionette-agent close --all
```

`close --all` also closes other sessions in the same daemon. Use individual closes during parallel work.

## Recover a lost connection

Connection loss, app exit, or daemon restart invalidates existing refs. For an externally launched app, explicitly reconnect using its current URI and take a fresh snapshot.

The daemon’s idle timeout defaults to one hour and is fixed at startup. Once all requests are idle and the timeout expires, recordings and connections are finalized. Check the idle setting before a long recording, too.

## Isolate parallel work

Separate devices, app checkouts, and artifact paths as well as sessions. Use `--namespace` or `MARIONETTE_AGENT_RUNTIME_DIR` when you also need separate daemons. Keep runtime paths private and short; the Unix socket path is limited to 80 UTF-8 bytes.

See [configuration](/marionette_agent/en/reference/configuration/) for defaults and options.
