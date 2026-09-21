# Workflow samples

These JSON/YAML files are inputs for `marionette-agent workflow`. They target the
[Flutter verification app](../../example/README.md) in `example/`.

| File | Purpose |
| --- | --- |
| [reach-controls.yaml](reach-controls.yaml) / [JSON](reach-controls.json) | Navigate between tabs, wait, swipe, and observe the Controls screen |
| [fill-input.json](fill-input.json) + [inputs.example.json](inputs.example.json) | Bind a required string input and fill the text field |
| [headless-controls.yaml](headless-controls.yaml) / [JSON](headless-controls.json) | Exercise Controls after a managed headless launch |
| [all-actions.yaml](all-actions.yaml) | Run all six workflow actions in a 16-step scenario |
| [stop-on-missing.json](stop-on-missing.json) | Demonstrate stopping at a missing target after the first action |

From the repository root, resolve workspace dependencies with `flutter pub get`.
Validate a sample without connecting to an app:

```sh
dart run bin/marionette_agent.dart workflow validate samples/workflows/reach-controls.yaml --json
dart run bin/marionette_agent.dart workflow validate samples/workflows/fill-input.json --inputs samples/workflows/inputs.example.json --json
```

After starting the example and connecting the CLI session to its current VM Service
URI, run a sample from the same directory:

```sh
dart run bin/marionette_agent.dart workflow run samples/workflows/reach-controls.yaml --json
```

See the [workflow guide](../../website/src/content/docs/en/guides/workflows.md)
([日本語](../../website/src/content/docs/ja/guides/workflows.md)) for usage, and
[runtime verification](../../docs/runtime-verification.md)
([日本語](../../docs/ja/runtime-verification.ja.md)) for fixture preparation,
acceptance criteria, evidence, and cleanup.
