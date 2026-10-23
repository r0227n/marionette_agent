# Contributing

Open an [issue](https://github.com/r0227n/marionette_agent/issues) with a minimal
reproduction, CLI/platform versions, Flutter/Dart versions, macOS version, and target
runtime. Redact credentials and personal data. Security reports follow
[SECURITY.md](SECURITY.md).

Read [AGENTS.md](AGENTS.md), [SPEC](docs/SPEC.md), and
[architecture](docs/ARCHITECTURE.md) before changing code. Base PRs on `develop`;
follow the repository's branch/worktree rules and keep changes focused. The root Pub
workspace resolves CLI, platform packages, and example together.

Use [mise](https://mise.jdx.dev/) to manage [Lefthook](https://lefthook.dev/).
Run `mise install` at the repository root to install the pinned versions in
`.mise.toml` (Lefthook 2.2.1 and Bun 1.4.2), and install ffmpeg separately
(`brew install ffmpeg`).
Run `mise exec -- lefthook install` once after cloning and in each new worktree.
The installed Git hook also invokes Lefthook through mise, using the same pin.
Resolve dependencies once at the root with
`flutter pub get --enforce-lockfile`.

The pre-commit hook checks staged Dart formatting and runs the full workspace
gate for Dart, YAML, JSON, lockfile, and distribution inputs. Documentation-only and
website-only commits skip that gate; website checks remain in the Documentation
workflow. Hooks check without rewriting or automatically staging your files.
Run `mise exec -- lefthook run pre-commit --all-files` for the complete gate, including before
handoff; the [release checks](docs/releasing.md#local-gates) describe its scope
and the separate website/native checks. The former Quality PR workflow is removed.
Release preparation and handoff assume the exact candidate passed these checks
locally; they do not install or run Lefthook in CI.
Behavior changes also need example-app verification on iOS Simulator
under the repository's resource-coordination rules. A tester smoke is additional
coverage, not evidence of native platform behavior.

Update paired English/Japanese pages and supplements in the same change; use
[documentation policy](docs/documentation.md) and [website checks](website/README.md).
Do not edit externally managed skills or remove their lock entries. Dependency
changes must refresh and review third-party notices. Public CLI/platform contracts
follow the [1.x compatibility policy](website/src/content/docs/en/reference/compatibility.md).

Contributions to original project material are accepted under Apache-2.0;
retain attribution and licenses for third-party material. Maintainer review and
human acceptance precede release. Do not publish artifacts or change repository
permissions as part of an ordinary contribution.
