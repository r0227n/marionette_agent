---
title: Command reference
description: Find CLI syntax for connections, observation, interaction, capture, and management.
---

In the tables, `TARGET` means a current ref or a selector such as `--key`, `--text`, or `--type`. See [target selection](/marionette_agent/en/concepts/targets/) for details. Common options can appear before or after the command.

## Connect and launch

| Syntax                               | Result or requirement                                                                                                                  |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| `connect URI`                        | Connect to a running debug app; HTTP(S) URIs are normalized to WS(S)                                                                   |
| `launch PROJECT --platform PLATFORM` | Build, launch, connect, and observe; see [launching environments](/marionette_agent/en/guides/headless/) for platform-specific options |
| `session list`                       | List daemon sessions; empty if no daemon exists                                                                                        |
| `session show`                       | Selected session state and a redacted connection destination                                                                           |
| `close`                              | Close the selected session and any app it launched                                                                                     |
| `close --all`                        | Close all daemon sessions; cannot be combined with explicit `--session`                                                                |

## Observe and inspect

| Syntax                                       | Result or requirement                                                      |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| `snapshot`                                   | Fresh observation and refs; previous refs expire                           |
| `snapshot --key KEY`                         | Exact-match observation filter; text, type, or identifier are alternatives |
| `snapshot --interactive --compact --depth N` | Adjust interaction candidates, detail, and observation depth               |
| `get text TARGET`                            | Display text; null when unavailable                                        |
| `get box TARGET`                             | Bounds with unit `flutter_logical_pixels`; null when unavailable           |
| `get count SELECTOR`                         | Count observed candidates; refs are rejected, zero is successful           |
| `get value TARGET`                           | Typed input value; requires a compatible provider                          |
| `is visible TARGET`                          | Visibility as known/value                                                  |
| `is enabled TARGET` / `is checked TARGET`    | Provider-backed state; unknown when not observed                           |
| `logs`                                       | Retrieve collected logs; not a continuous subscription                     |

Successful get and is queries read observations without issuing new refs. Do not interpret `unknown` as false.

## Tap, enter text, and gesture

| Syntax                                                | Behavior                                                |
| ----------------------------------------------------- | ------------------------------------------------------- |
| `tap TARGET` / `click TARGET`                         | The same tap operation                                  |
| `tap --x X --y Y`                                     | Tap Flutter logical coordinates                         |
| `fill TARGET TEXT`                                    | Replace the entire input; an empty string clears it     |
| `swipe TARGET DIRECTION --distance N`                 | Move a finger from the target; distance defaults to 200 |
| `swipe --start-x X --start-y Y --end-x X2 --end-y Y2` | Gesture from explicit start to end coordinates          |
| `scroll TARGET DIRECTION --distance N`                | Send a scroll gesture to the target region              |

Directions are `left`, `right`, `up`, and `down`, describing **finger movement**. Verify the resulting content position or page in a subsequent snapshot.

## Operations with auxiliary providers

The following need a compatible app-side provider. Try them on the example app’s Advanced screen.

| Syntax                                            | Behavior                                                          |
| ------------------------------------------------- | ----------------------------------------------------------------- |
| `dblclick TARGET`                                 | Two taps                                                          |
| `focus TARGET` / `hover TARGET`                   | Input focus or synthetic mouse event                              |
| `type TARGET TEXT`                                | Insert at the selection; append if the selection is invalid       |
| `check TARGET` / `uncheck TARGET`                 | Set a Checkbox or Switch to the desired state                     |
| `select TARGET VALUE`                             | Select a DropdownButton string value                              |
| `scrollintoview TARGET`                           | ensureVisible on a mounted element; does not search unbuilt items |
| `drag FROM_REF TO_REF`                            | Touch gesture between two targets                                 |
| `drag --from-key KEY --to-key KEY2`               | Drag between two key-selected targets                             |
| `press KEYS`                                      | Press and release a key combination, such as `Control+A`          |
| `keydown KEY` / `keyup KEY`                       | Hold or release one key                                           |
| `keyboard press KEYS`                             | Send a key combination to the focused control                     |
| `keyboard type TEXT` / `keyboard inserttext TEXT` | Insert text into the focused EditableText                         |
| `clipboard read` / `clipboard write TEXT`         | Read or write the clipboard                                       |
| `clipboard copy` / `clipboard paste`              | Copy or paste at the focused control                              |

## Find and wait

`find` supports role, label, placeholder, text, key, identifier, and type queries. Use `--exact` for exact matching; role queries also accept `--name`. Append an action and input value when needed.

```sh
marionette-agent find label 'Editable' focus
marionette-agent find key advanced_input type 'hello'
marionette-agent wait --key about_content --timeout 5000
marionette-agent wait --key loading --state gone --poll-interval 100
```

Ordered selection is also available with `find first SELECTOR`, `find last SELECTOR`, and `find nth INDEX SELECTOR`.

The default `wait` state is `exists`: a unique match with `visible != false` succeeds. `gone` waits until there are zero matches. Poll intervals range from 50 to 1,000ms and default to 100ms. `wait REF` and `wait MILLISECONDS` are also supported. Check the returned `requiresSnapshot` to decide whether a fresh snapshot is needed.

## Images, recordings, and differences

| Syntax                                                  | Purpose                                                          |
| ------------------------------------------------------- | ---------------------------------------------------------------- |
| `screenshot [PATH]`                                     | Save a new image                                                 |
| `screenshot TARGET [PATH]`                              | Capture the target region                                        |
| `screenshot --annotate [PATH]`                          | Overlay refs; requires a provider and valid snapshot             |
| `record start PATH --platform PLATFORM [--device ID]`   | Start recording; Flutter rendering needs no device argument      |
| `record restart PATH --platform PLATFORM [--device ID]` | Finalize the current recording and start a new one               |
| `record status` / `record stop`                         | Inspect recording state or finalize and stop                     |
| `diff snapshot --baseline PATH`                         | Compare with a saved snapshot                                    |
| `diff screenshot --baseline PATH`                       | Compare with a saved image; accepts `--threshold` and `--output` |

See [capture](/marionette_agent/en/guides/capture/) for file requirements and platform differences.

## Automation, configuration, and management

| Syntax                                         | Purpose                                                                     |
| ---------------------------------------------- | --------------------------------------------------------------------------- |
| `workflow schema [ACTION]`                     | Retrieve the bundled schema                                                 |
| `workflow validate PATH` / `workflow run PATH` | Validate or execute a workflow                                              |
| `batch PATH`                                   | Execute a JSON array of argument arrays; set common options on batch itself |
| `state save PATH` / `state load PATH`          | Save only the connection URI to a private file or reconnect from it         |
| `confirm ID` / `deny ID`                       | Approve or reject a pending action                                          |
| `device list --platform ios`                   | List available iOS devices; android is also supported                       |
| `doctor`                                       | Diagnose the local environment; `--probe-uri` also queries an app           |
| `doctor --quick` / `--offline` / `--fix`       | Limit checks, skip the VM probe, or repair owned runtime permissions        |
| `install DIRECTORY` / `upgrade DIRECTORY`      | Install or update the executable and Skills from local source               |
| `skills list` / `get` / `path`                 | Access bundled instructions                                                 |
| `mcp --tools PROFILES`                         | Start the stdio MCP server                                                  |
| `--help` / `--version`                         | Read usage or version without a connection                                  |

Batch stops at the first failure and cannot contain connection-lifetime operations, recording, or file-saving commands. See [configuration](/marionette_agent/en/reference/configuration/) for action policies and state files.
