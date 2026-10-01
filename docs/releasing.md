# Release preparation and distribution

[日本語](ja/releasing.ja.md)

## Current route and scope

Released versions use immutable Git tags and GitHub Releases with source archives.
For 1.0.0, select `v1.0.0`, resolve the committed lockfile, and compile locally.
Keep `publish_to: none` in CLI/util/example; global Pub activation and pub.dev
publication are not supported. Development installations may select a reviewed
`develop` commit and must record that SHA instead of assuming release behavior.

The installer distributes the native executable and its matching sibling
`.marionette-agent-*` directory with Skills and LICENSE/NOTICE/THIRD_PARTY_NOTICES.
Retain all of these when moving or redistributing a binary. Upgrades preserve old
bundles; remove only those no installed executable uses. App-side util is consumed
from the same checkout. No prebuilt multi-platform assets are promised.

## Licensing audit

Original project code/docs use Apache-2.0, following
[leancodepl/marionette_mcp's LICENSE](https://github.com/leancodepl/marionette_mcp/blob/main/LICENSE)
(blob `261eeb9e9f8b2b4b0d119366dda99c6fd7d35c64`, checked 2026-10-01).
NOTICE names this project's contributors without appropriating upstream ownership.
The dependency files remain verbatim in THIRD_PARTY_NOTICES.txt. The generator
walks **production** dependencies of CLI/util/example, including app-side Flutter/engine
notices and the Dart runtime. It fails on missing licenses; `--check` rejects
stale notices. It deliberately overincludes the declared closure instead of
claiming every package is linked into the AOT executable.

Runtime dependencies include Apache-2.0 Marionette, MIT image/archive libraries,
and BSD Dart/Flutter packages. Preserve original notices. Resolve the committed
lockfile with Flutter 3.47.2 before generating. Dependency/SDK changes require a
fresh audit, including embedded assets and nested third-party notices in packages.
The generated file is not an automated legal compatibility verdict.

The externally managed development skills listed in skills-lock.json come from
[mattpocock/skills](https://github.com/mattpocock/skills) under MIT; their original
notice is retained in `third_party/mattpocock-skills-LICENSE` (upstream LICENSE
blob `f1dd2c09108dde1a5f56097cee8461b3ea834499`). They are not installed with the CLI.
The bundled Skills are this project's material. The example contains Flutter
scaffold/icons; retain Flutter/engine and cupertino_icons notices if distributing
an example build. Website build tooling is not included in the CLI binary;
redistribution of generated sites or new bundled assets needs its own scope audit.

## Local gates

Use the pinned baseline Flutter 3.47.2 / Dart 3.13.2 on macOS. Run from the root,
then the indicated member directories. `--concurrency=1` avoids process-heavy
test contention. The CLI test runner's `--timeout=2m` includes cold child-process
JIT startup on hosted macOS; product deadlines and explicit test timeouts still
apply. The tester smoke builds no native app and boots no Simulator.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed bin lib test tool integration_test packages/marionette_agent_util/lib packages/marionette_agent_util/test packages/marionette_agent_util/flutter_test example/lib example/test
dart analyze
dart run tool/check_release.dart
dart run tool/license_notices.dart --check
dart test --concurrency=1 --timeout=2m
(cd packages/marionette_agent_util && dart test --concurrency=1 && flutter test flutter_test)
(cd example && flutter test)
dart run integration_test/release_smoke.dart
(cd website && bun install --frozen-lockfile && bun run verify)
```

After dependency changes, regenerate `dart run tool/license_notices.dart`, review
notices, and rerun the check. The smoke installs into a fresh private directory,
checks version and notices, launches/connects tester, observes tap=0, taps to 1,
fills to 5 characters, captures, closes, and verifies daemon cleanup. It redacts
raw output and preserves a live runtime if cleanup fails. Set
`MARIONETTE_RELEASE_SCREENSHOT` to a private absolute file path to retain the
capture for visual inspection. A tester result does not establish native/iOS
behavior; follow [runtime verification](runtime-verification.md) and coordinate
Simulator resources before native acceptance checks.

## Publication checklist

- [ ] Release changes are reviewed and integrated into `develop`; final tree is clean.
- [ ] Above gates and required iOS/native acceptance pass on the exact candidate.
- [ ] Fresh source checkout/locked resolution/install/smoke succeed; inspect capture.
- [ ] License notices match exact dependencies, SDK, and chosen distribution assets.
- [ ] Confirm SECURITY points to the requested public Issues tracker and warns
      against posting secrets, personal information, tokens, or abuse-enabling
      details. GitHub private reporting was disabled at the 2026-10-01 read-only
      check; no private route or setting change is promised.
- [ ] CLI/util pubspec, CLI/MCP version, CHANGELOG, tag, and Release agree on 1.0.0.
- [ ] Installation examples use `v1.0.0`; verify the tag after publishing.
- [ ] Keep the site as development documentation published from `develop`; stable
      installation instructions select the release tag. The banner SHA is the
      site build revision, not a promise of the latest release.
- [ ] Obtain authorization for push/PR/merge/tag/Release; hosting or permission
      changes require their own scope.
- [ ] Confirm Pages deploy and live URLs when authorized. Run 35617308091 built,
      checked, and uploaded successfully; deploy creation returned HTTP 500 from
      GitHub. Existing workflow gates and artifact/environment names are consistent;
      logs do not prove a configuration defect. After the user merged PR #48,
      run [36854804049](https://github.com/r0227n/marionette_agent/actions/runs/36854804049)
      succeeded, including verify and deploy. No redeploy was requested by this task.

Do not remove `publish_to: none` as a release shortcut. A future pub.dev decision
needs workspace/path dependency design and a separate package-content dry run.
