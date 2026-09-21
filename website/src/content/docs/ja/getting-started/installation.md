---
title: CLIをインストールする
description: ローカルcheckoutからmarionette-agentをビルドし、更新する。
---

現在はリポジトリのソースからCLIを導入します。Dart SDK 3.13.2以上・4.0.0未満とFlutter SDKを用意してください。exampleではFlutter 3.47.2を使用しています。

## ソースを取得する

```sh
git clone --branch develop https://github.com/r0227n/marionette_agent.git
cd marionette_agent
```

ページ上部のコミットと同じ内容を使う場合は、そのリンク先の完全なSHAを取得し、`DOCUMENTED_COMMIT`を置き換えて実行します。

```sh
git switch --detach DOCUMENTED_COMMIT
```

## CLIと同梱Skillsを配置する

リポジトリルートから実行します。

```sh
cd packages/marionette_agent
flutter pub get
mkdir -p "$HOME/.local/bin"
dart run bin/marionette_agent.dart install "$HOME/.local/bin" --timeout 120000
export PATH="$HOME/.local/bin:$PATH"
marionette-agent --version
```

`install`はCLIをコンパイルし、指定した既存ディレクトリへ配置します。同じ名前の実行ファイルが存在すると失敗します。バイナリの隣に作られる`.marionette-agent-*`ディレクトリは同梱Skillsに必要です。バイナリを移す場合は、このディレクトリも一緒に移してください。

PATHの設定を次回のシェルでも使うには、利用しているシェルの設定ファイルに同じexportを追加します。

## コンパイルせずに試す

依存取得後の`packages/marionette_agent`内では、Dartから直接実行できます。

```sh
dart run bin/marionette_agent.dart --help
```

以降の説明で使う`marionette-agent`を、このDart entrypointで置き換えることもできます。

## 更新する

使いたいコミットをcheckoutし、CLIパッケージで依存を取得し直した後、リポジトリルートから実行します。

```sh
marionette-agent upgrade --source packages/marionette_agent \
  "$HOME/.local/bin" --timeout 120000
```

`upgrade`はローカルソースのコンパイルが成功してから既存バイナリを置き換えます。ソースのダウンロードやFlutter SDKの更新は別途行います。

導入できたら、[exampleで最初の操作](/marionette_agent/ja/getting-started/quick-start/)へ進みます。
