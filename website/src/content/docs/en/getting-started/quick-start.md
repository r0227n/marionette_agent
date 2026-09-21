---
title: Your first interaction
description: Connect to the example in iOS Simulator and verify a tap and a text edit.
---

In this walkthrough, you operate the visible iOS Simulator example through the CLI. Finish [installation](/marionette_agent/en/getting-started/installation/) and prepare Xcode and an available Simulator. You will use two terminals.

## 1. Start the example

Boot your chosen device in the Simulator app. In the first terminal, enter the repository’s `example` directory.

```sh
cd example
flutter pub get
flutter devices
```

Copy the iOS Simulator UDID from the list into `SIMULATOR_UDID` below. Use a dedicated URI file path for this run.

```sh
SIMULATOR_UDID='REPLACE_WITH_YOUR_SIMULATOR_UDID'
umask 077
flutter run -d "$SIMULATOR_UDID" --debug --no-pub \
  --vmservice-out-file=/tmp/marionette-docs-uri
```

Wait until the example’s Controls screen appears, and leave this terminal running. The URI contains connection credentials. Keep it out of shared logs and screenshots.

## 2. Connect and observe

In the second terminal, select a session for the following operations.

```sh
export MARIONETTE_AGENT_SESSION=docs-demo
marionette-agent connect "$(cat /tmp/marionette-docs-uri)"
marionette-agent snapshot
```

Check that the output contains elements with the `tap_button` and `text_input` keys. Ref numbers such as `@e1` change between observations, so this walkthrough uses keys defined in the example.

## 3. Tap and check the change

```sh
marionette-agent tap --key tap_button
marionette-agent get text --key tap_result
marionette-agent snapshot
```

The tap count in `tap_result` should increase by one, with the same result visible in Simulator. It will be one if you started from the initial state.

## 4. Enter text

```sh
marionette-agent fill --key text_input 'hello'
marionette-agent snapshot
```

Check that the field displays `hello`. `fill` replaces the entire existing value. You can now capture the screen.

```sh
marionette-agent screenshot
```

Open the image at the returned path and confirm it shows the screen after the text edit.

## 5. Close the connection

```sh
marionette-agent close
unset MARIONETTE_AGENT_SESSION
```

Closing a connection to an externally launched app leaves that app running. Stop the Flutter runner in the first terminal, then remove the URI file when you no longer need it.

```sh
rm /tmp/marionette-docs-uri
```

Read [the observation loop](/marionette_agent/en/concepts/observation-loop/) next to understand refs and result verification. If connection fails, see [troubleshooting](/marionette_agent/en/reference/troubleshooting/).
