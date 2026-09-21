---
title: Install the CLI
description: Build and update marionette-agent from a local checkout.
---

Install the CLI from the repository source. You need Dart SDK 3.13.2 or newer, below 4.0.0, and a Flutter SDK. The example uses Flutter 3.47.2.

## Get the source

```sh
git clone --branch develop https://github.com/r0227n/marionette_agent.git
cd marionette_agent
```

To use the exact revision described by these docs, open the commit link in the page banner, copy its full SHA, and replace `DOCUMENTED_COMMIT` below.

```sh
git switch --detach DOCUMENTED_COMMIT
```

## Install the CLI and bundled Skills

Start in the repository root.

```sh
cd packages/marionette_agent
flutter pub get
mkdir -p "$HOME/.local/bin"
dart run bin/marionette_agent.dart install "$HOME/.local/bin" --timeout 120000
export PATH="$HOME/.local/bin:$PATH"
marionette-agent --version
```

`install` compiles the CLI into the existing destination directory. It fails if the executable already exists. The adjacent `.marionette-agent-*` directory contains the bundled Skills. Move that directory together with the executable if you relocate the installation.

Add the same PATH export to your shell configuration if you want it to persist across new shells.

## Try the source entrypoint

After resolving dependencies, you can run Dart directly inside `packages/marionette_agent`.

```sh
dart run bin/marionette_agent.dart --help
```

You can substitute this Dart entrypoint for `marionette-agent` in the rest of the documentation.

## Update an installation

Check out your desired revision and refresh dependencies in the CLI package. Then run this from the repository root.

```sh
marionette-agent upgrade --source packages/marionette_agent \
  "$HOME/.local/bin" --timeout 120000
```

`upgrade` replaces the existing executable only after compiling the local source successfully. Download source updates and update your Flutter SDK separately.

Continue with [your first interaction](/marionette_agent/en/getting-started/quick-start/).
