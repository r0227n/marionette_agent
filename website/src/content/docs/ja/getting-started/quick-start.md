---
title: exampleで最初の操作
description: iOS Simulator上のexampleに接続し、タップと入力の結果を確かめる。
---

この手順では、iOS Simulatorに表示したexampleをCLIから操作します。[CLIの導入](/marionette_agent/ja/getting-started/installation/)を終え、Xcodeと利用可能なSimulatorを用意してください。ターミナルを2つ使います。

## 1. exampleを起動する

Simulatorアプリで使う端末を起動します。1つ目のターミナルで、リポジトリの`example`ディレクトリへ移動します。

```sh
cd example
flutter pub get
flutter devices
```

一覧からiOS SimulatorのUDIDをコピーし、次の`SIMULATOR_UDID`へ設定します。URIファイルは今回の作業で使う専用パスを指定してください。

```sh
SIMULATOR_UDID='REPLACE_WITH_YOUR_SIMULATOR_UDID'
umask 077
flutter run -d "$SIMULATOR_UDID" --debug --no-pub \
  --vmservice-out-file=/tmp/marionette-docs-uri
```

exampleのControls画面が表示されるまで待ち、このターミナルは起動したままにします。URIには接続用の認証情報が含まれます。共有するログやスクリーンショットに写さないでください。

## 2. 接続して観測する

2つ目のターミナルで、以降の操作に使うsessionを選びます。

```sh
export MARIONETTE_AGENT_SESSION=docs-demo
marionette-agent connect "$(cat /tmp/marionette-docs-uri)"
marionette-agent snapshot
```

出力に`tap_button`と`text_input`を持つ要素があることを確認します。snapshotの`@e1`などの番号は実行ごとに変わるため、この手順ではexampleに定義されたkeyを使います。

## 3. タップして、変化を確かめる

```sh
marionette-agent tap --key tap_button
marionette-agent get text --key tap_result
marionette-agent snapshot
```

`tap_result`のタップ数が操作前より1増え、Simulatorにも同じ結果が表示されれば成功です。初期状態から開始した場合は1になります。

## 4. 文字を入力する

```sh
marionette-agent fill --key text_input 'hello'
marionette-agent snapshot
```

入力欄が`hello`になっていることを画面で確認します。`fill`は既存の入力全体を置き換えます。続けて画面を保存できます。

```sh
marionette-agent screenshot
```

返された保存先の画像を開き、入力後の画面であることを確認してください。

## 5. 接続を閉じる

```sh
marionette-agent close
unset MARIONETTE_AGENT_SESSION
```

今回のように外部で起動したアプリへの`connect`を閉じても、アプリは動いたままです。1つ目のターミナルでFlutter runnerを終了した後、不要なURIファイルを削除します。

```sh
rm /tmp/marionette-docs-uri
```

次は[観測と操作の流れ](/marionette_agent/ja/concepts/observation-loop/)で、refの扱いと結果の確認方法を理解します。接続できない場合は[トラブルシューティング](/marionette_agent/ja/reference/troubleshooting/)を参照してください。
