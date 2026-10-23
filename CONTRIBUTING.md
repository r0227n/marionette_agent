# Contributing

Open an [issue](https://github.com/r0227n/marionette_agent/issues) with a minimal
reproduction, CLI/util versions, Flutter/Dart versions, macOS version, and target
runtime. Redact credentials and personal data. Security reports follow
[SECURITY.md](SECURITY.md).

Read [AGENTS.md](AGENTS.md), [SPEC](docs/SPEC.md), and
[architecture](docs/ARCHITECTURE.md) before changing code. Base PRs on `develop`;
follow the repository's branch/worktree rules and keep changes focused. The root Pub
workspace resolves CLI, util, and example together.

Install [Lefthook](https://lefthook.dev/) 2.2.1 or newer and ffmpeg on macOS
(`brew install lefthook ffmpeg`). Mise users can install the pinned Lefthook from
the root `.tool-versions`. Run `lefthook install` once after cloning; also run it
in each new worktree. Resolve dependencies once at the root with
`flutter pub get --enforce-lockfile`.

The pre-commit hook checks staged Dart formatting and runs the full workspace
gate for Dart, YAML, JSON, lockfile, and distribution inputs. Documentation-only and
website-only commits skip that gate; website checks remain in the Documentation
workflow. Hooks check without rewriting or automatically staging your files.
Run `lefthook run pre-commit --all-files` for the complete gate, including before
handoff; the [release checks](docs/releasing.md#local-gates) describe its scope
and the separate website/native checks. The former Quality PR workflow is removed;
release preparation and handoff still run the same Lefthook gate on the exact SHA.
Behavior changes also need example-app verification on iOS Simulator
under the repository's resource-coordination rules. A tester smoke is additional
coverage, not evidence of native platform behavior.

Update paired English/Japanese pages and supplements in the same change; use
[documentation policy](docs/documentation.md) and [website checks](website/README.md).
Do not edit externally managed skills or remove their lock entries. Dependency
changes must refresh and review third-party notices. Public CLI/util contracts
follow the [1.x compatibility policy](website/src/content/docs/en/reference/compatibility.md).

Contributions to original project material are accepted under Apache-2.0;
retain attribution and licenses for third-party material. Maintainer review and
human acceptance precede release. Do not publish artifacts or change repository
permissions as part of an ordinary contribution.
