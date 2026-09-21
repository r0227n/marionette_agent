---
title: 自分のアプリへ組み込む
description: Flutterのdebug起動でMarionette bindingを初期化し、観測しやすい対象を用意する。
---

アプリ側でMarionette bindingを有効にすると、CLIからVM Serviceを通じて観測・操作できます。まずdebug起動だけで有効になる入口を用意します。

## bindingを初期化する

アプリのディレクトリで依存を追加します。

```sh
flutter pub add marionette_flutter:0.6.0
```

次の初期化を`runApp`より前に組み込みます。`MyApp`は既存アプリのroot widgetに置き換えてください。

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

void main() {
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  runApp(const MyApp());
}
```

他の初期化がbindingを要求する場合も、Marionette bindingの初期化を先に行います。アプリをdebugで起動し、その実行のVM Service URIで`connect`してください。

## 安定したkeyを付ける

操作手順から参照したいwidgetには、一意なkeyを付けます。表示文言の変更や翻訳に依存しにくくなります。

```dart
TextField(key: const ValueKey('email'))
```

```sh
marionette-agent snapshot
marionette-agent fill --key email 'reader@example.com'
marionette-agent snapshot
```

同じkeyの対象が複数観測されると操作は拒否されます。画面単位で対象が一意になるよう設計してください。

## 追加providerを使う

`get value`、`is checked`、追加の入力操作などには`marionette_agent_util`のFlutter拡張を登録します。現状はこのリポジトリ内のローカルパッケージです。アプリの依存にcheckout内の`packages/marionette_agent_util`へのpathを設定し、bindingの初期化後に登録します。

```dart
import 'package:marionette_agent_util/flutter.dart';

// After MarionetteBinding.ensureInitialized(), in the debug branch:
registerAgentExtensions();
```

exampleには登録済みです。注釈付きスクリーンショットには、これとは別にboundsを画像へ対応付けるmapped screenshot providerが必要です。

[exampleの初期化コード](https://github.com/r0227n/marionette_agent/blob/develop/example/lib/main.dart)と[補助パッケージ](https://github.com/r0227n/marionette_agent/tree/develop/packages/marionette_agent_util)で実装例を確認できます。登録していない機能は`UNSUPPORTED_CAPABILITY`となる場合があり、未観測の値は空文字やfalseとは区別されます。
