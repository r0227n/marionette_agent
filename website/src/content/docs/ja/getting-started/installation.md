---
title: CLIをインストールする
description: ローカルcheckoutからmarionette-agentをビルドし、更新する。
---

現在はリポジトリのソースからCLIを導入します。Dart SDK 3.13.2以上・4.0.0未満とFlutter SDKを用意してください。exampleではFlutter 3.47.2を使用しています。

1.0.0の固定タグからソースを取得し、手元でコンパイルします。GitHub Releaseはリリースノートとソースarchiveを提供し、pub.dev公開は無効のままです。文書サイトは`develop`を追跡しますが、導入はリリースタグで固定します。

## ソースを取得する

```sh
git clone --branch v1.0.0 https://github.com/r0227n/marionette_agent.git
cd marionette_agent
```

開発版を使う場合だけの任意手順です。公開版1.0.0の導入では省略してください。この文書の開発基点と同じ内容を使う場合は、ページ上部のコミットから完全なSHAを取得し、`DOCUMENTED_COMMIT`を置き換えて実行します。

```sh
git switch --detach DOCUMENTED_COMMIT
```

## CLIと同梱Skillsを配置する

リポジトリルートがCLIパッケージ兼Pub workspaceのルートです。ここで `flutter pub get` を一度実行すると、CLI・util・exampleの依存をまとめて解決します。ルートの `pubspec.lock` とpackage configを共有します。

```sh
flutter pub get --enforce-lockfile
mkdir -p "$HOME/.local/bin"
dart run bin/marionette_agent.dart install "$HOME/.local/bin" --timeout 120000
export PATH="$HOME/.local/bin:$PATH"
marionette-agent --version
```

`install`はCLIをコンパイルし、指定した既存ディレクトリへ配置します。同じ名前の実行ファイルが存在すると失敗します。バイナリの隣に作られる`.marionette-agent-*`ディレクトリは同梱Skillsと`LICENSE`、`NOTICE`、`THIRD_PARTY_NOTICES.txt`を保持します。バイナリを移す場合は、このディレクトリも一緒に移してください。

PATHの設定を次回のシェルでも使うには、利用しているシェルの設定ファイルに同じexportを追加します。

## コンパイルせずに試す

依存取得後はリポジトリルートで、Dartから直接実行できます。

```sh
dart run bin/marionette_agent.dart --help
```

以降の説明で使う`marionette-agent`を、このDart entrypointで置き換えることもできます。

## 更新する

使いたいコミットをcheckoutし、リポジトリルートでworkspaceの依存を取得し直した後、同じ場所から実行します。

```sh
marionette-agent upgrade --source . \
  "$HOME/.local/bin" --timeout 120000
```

`upgrade`はローカルソースのコンパイルが成功してから既存バイナリを置き換えます。ソースのダウンロードやFlutter SDKの更新は別途行います。

導入できたら、[exampleで最初の操作](/marionette_agent/ja/getting-started/quick-start/)へ進みます。
