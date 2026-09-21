---
title: Capabilities and requirements
description: Understand the relationship between the CLI, your Flutter app, and its execution environment.
---

marionette-agent reads a running Flutter app and operates on explicitly selected targets. Use it to investigate test procedures, let an agent interact with a UI, and check the resulting state.

The CLI communicates with the app’s Marionette binding through the Dart VM Service. Prepare an observable app before starting a connection.

## What you need

| Component                                | Requirement                                                              |
| ---------------------------------------- | ------------------------------------------------------------------------ |
| CLI host                                 | macOS. Linux and Windows hosts are currently outside the supported scope |
| CLI build                                | Dart 3.13.2 or newer, below 4.0.0, and a Flutter SDK                     |
| Target app                               | A debug app initialized with `marionette_flutter` 0.6.0                  |
| Connection to an externally launched app | The VM Service URI for that run                                          |
| First check on iOS                       | Xcode, an available iOS Simulator, and the bundled example               |

The example has been verified with Flutter 3.47.2. Starting with this combination helps separate SDK differences from app integration problems.

## Available operations

- Observe screens and retrieve element text, bounds, and state.
- Tap, enter text, swipe, scroll, and wait for a condition.
- Manage named sessions, read JSON results, and run sequential workflows.
- Save images and recordings, and call tools through MCP.

Some additional input and inspection operations require an app-side provider. See [app integration](/marionette_agent/en/getting-started/app-integration/) for preparation.

## Choose an execution environment

The introductory path connects to the example running in an iOS Simulator you start yourself. With `launch`, you can explicitly select tester, iOS, Android, macOS, or Web and connect the launched app to the session.

Tester is useful for repeated checks of shared Flutter UI. Choose the corresponding platform environment to check OS permissions, native plugins, or browser-specific behavior. See [headless execution](/marionette_agent/en/guides/headless/) for details.

## Interpret the result

A successful action response does not guarantee that your application-level goal was reached. After pressing a button, observe the screen again and check the expected value or element. Do not infer unbuilt lazy-list items or unobserved attributes from a snapshot.

These docs describe the development version. The banner on each page identifies the package version and commit. Continue with [installation](/marionette_agent/en/getting-started/installation/).
