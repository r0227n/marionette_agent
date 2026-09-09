# Marionette Agent

Marionette対応Flutterアプリを、macOSからiOS Simulator上で操作するDart CLIです。接続したsessionと最新snapshotのrefはdaemonが保持するため、別々のCLI呼出しで操作を続けられます。

パッケージディレクトリで`dart pub get`を実行し、`dart run bin/marionette_agent.dart --help`で起動できます。`dart pub global activate --source path .`で登録すると、以下の`marionette-agent`コマンドを使えます。Dart SDKはpubspecの制約に従ってください。

```sh
marionette-agent --session demo connect "$VM_URI" --json
marionette-agent --session demo snapshot --json
marionette-agent --session demo tap --key tap_button --json
marionette-agent --session demo snapshot --json
marionette-agent --session demo close --json
```

`VM_URI`は起動したアプリのVM Service URIです。[動作確認用アプリの起動手順](../../operation_confirmation/README.md)と[製品仕様](../../SPEC.md)を参照してください。`fill`は文字列を置換し、空文字でクリアします。`swipe`と`scroll`の方向は指の移動方向で、結果はsnapshotで確認します。

## Workflow

JSON/YAMLファイルで`snapshot`、`tap`、`fill`、`swipe`、`scroll`、`wait`を順番に実行できます。workflow全体で同一sessionのキューを占有し、最初の失敗で停止します。操作の自動retryやrollbackはありません。

まず接続し、必要なschemaと入力検証を確認します。以下の相対pathはパッケージディレクトリ基準です。

```sh
marionette-agent --session demo connect "$VM_URI" --json
marionette-agent workflow schema --json
marionette-agent workflow schema fill --json
marionette-agent workflow validate examples/workflows/reach-controls.yaml --json
marionette-agent workflow validate examples/workflows/fill-input.json --json
marionette-agent workflow validate examples/workflows/fill-input.json \
  --inputs examples/workflows/inputs.example.json --json
marionette-agent --session demo workflow run examples/workflows/reach-controls.yaml --json
```

schemaとvalidateはdaemonも接続も不要です。validateは通常templateのみを検証し、`--inputs`または`--check-inputs`で必要値のbindingまで確認します。runは常にbindingを検証します。UIの存在やselectorの一意性は実行時に確認します。

[reach-controls.yaml](examples/workflows/reach-controls.yaml)は動作確認アプリのAbout→Controls移動、PageViewの左swipe、最終snapshotを実行します。[JSON版](examples/workflows/reach-controls.json)も同じ操作です。返された`finalSnapshot.elements`で`text_input`のrefを確認し、その値を次の呼出しで使います。

```sh
# @e57は例。実際に返されたrefへ置き換える
marionette-agent --session demo fill @e57 'Workflow demo' --json
marionette-agent --session demo snapshot --json

# 値を外部から渡してworkflow内でfillする
marionette-agent --session demo workflow run examples/workflows/fill-input.json \
  --inputs examples/workflows/inputs.example.json --json
```

workflow内ではrefや座標を固定せず、key/identifier/text/typeのうち1つをtargetに指定します。binding 0.6.0ではidentifierは非対応です。waitは`exists`/`gone`をinspectで確認し、公開refを発行しません。最終snapshotの後にmutationがあると`finalSnapshot`は返らず、`requiresSnapshot:true`になります。返却後に別要求がsnapshotや操作を行うとrefは失効します。

拡張子は`.json`、`.yaml`、`.yml`を認識し、`--format`の指定が優先されます。stdinや不明な拡張子にはformatが必要です。inputs側には`--inputs-format`を使い、両方を同時にstdinにはできません。

```sh
marionette-agent workflow validate - --format json --json < flow.json
marionette-agent --session demo workflow run examples/workflows/fill-input.json \
  --inputs - --inputs-format json --json < private-inputs.json
```

秘密値はアクセス権を限定したinputsファイルやstdinで渡してください。入力引数を実行報告や診断へ複写しませんが、`sensitive:true`はdefault埋込みを禁止するmetadataです。**アプリが画面に表示した値はsnapshotにも含まれ得ます。** snapshotのマスキング機能はありません。

workflowとinputsは各1 MiB、stepは1〜100件、入れ子は32段、input/default/literalはUTF-8で64 KiBまでです。JSONの重複key、YAMLの重複key・tag・anchor・alias・merge・複数documentを拒否します。全体timeoutは既定30秒で、読込・キュー待ち・全stepを含みます。

失敗時は`error.details.completedSteps`と`stepIndex`（1始まり）で進捗を確認します。`outcome`は失敗stepの送信状態です。`not_sent`でも先行stepは実行済みの場合があります。配送結果が不明なら`progressKnown:false`です。現在の画面をsnapshotで確認してから必要な操作を判断し、workflow全体を自動で再実行しないでください。通信断やtimeout後は再connectが必要です。

IPC protocolは2です。旧daemonが残っている場合は旧CLIでsessionをcloseし、新CLIでconnectしてください。public JSON schemaVersionとworkflow schemaVersionは1です。

完全な契約は[workflow仕様](docs/workflow-file-spec.md)、実証結果は[Simulator検証記録](docs/verification/workflow-v1-2026-09-09.md)を参照してください。
