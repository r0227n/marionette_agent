# marionette_agent

AIエージェント向けの、Marionette対応Flutterアプリを観測・操作するDart製CLIです。

session、snapshot、短い要素参照（`@e1`）、JSON出力を使って、画面を観測し、対象を選んで操作し、操作後の状態を再び確認できます。

実行コマンドは `marionette-agent`。macOS・Linux・WindowsからFlutterアプリを操作できることを目指しています。現在の初版はmacOSを実行ホストとし、主にiOS Simulator上のdebug実行中のFlutterアプリを操作します。Simulatorやアプリのビルド・起動は別途行います。

## インストール

### 必要な環境

- Dart SDK 3.13.2以上、4.0.0未満
- ソースからのCLI依存取得と対象アプリのビルド・起動に必要なFlutter SDK（同梱exampleの使用バージョンは3.47.2）
- `marionette_flutter: 0.6.0`のbindingを初期化したdebugアプリと、そのVM Service URI

実行ホストの対応状況は次のとおりです。

| OS | 対応状況 |
| --- | --- |
| macOS | 現在の初版の対応環境 |
| Linux | 今後の対応目標 |
| Windows | 今後の対応目標 |

iOS Simulatorを操作する場合は、macOS上にXcodeと利用可能なiOS Simulatorが必要です。以下の導入・クイックスタートは、現在対応しているmacOS向けの手順です。

### ソースから導入する

このリポジトリのローカルcheckoutからCLIをコンパイルして配置します。

```bash
git clone https://github.com/r0227n/marionette_agent.git
cd marionette_agent
cd packages/marionette_agent
flutter pub get

mkdir -p "$HOME/.local/bin"
dart run bin/marionette_agent.dart install "$HOME/.local/bin" --timeout 120000
export PATH="$HOME/.local/bin:$PATH"

marionette-agent --version
marionette-agent --help
```

継続して使う場合は、シェルの設定にも `$HOME/.local/bin` をPATHへ追加してください。`install`は既存の実行ファイルを上書きしません。バイナリの隣に作成される `.marionette-agent-*` ディレクトリには同梱Skillが入るため、配布先へ移動する際は一緒に移動します。

コンパイルせずに使う場合は、`packages/marionette_agent` 内で次のように実行できます。以降の例の `marionette-agent` を `dart run bin/marionette_agent.dart` に置き換えてください。

```bash
dart run bin/marionette_agent.dart --help
```

### 更新

目的の版のcheckoutと依存関係を用意したうえで、リポジトリルートから実行します。

```bash
marionette-agent upgrade --source packages/marionette_agent \
  "$HOME/.local/bin" --timeout 120000
```

`upgrade`はコンパイル成功後に既存バイナリを置き換えます。ネットワークから最新版を取得したり、Flutter SDKを更新したりする機能ではありません。

## クイックスタート

### 1. exampleアプリを起動する

リポジトリルートから、同梱の[検証用アプリ](../../example/README.md)を起動します。Simulatorを起動し、`flutter devices`に表示される対象のUDIDを指定してください。

```bash
cd example
flutter pub get
flutter devices

# URIファイルを他ユーザーから読めないようにする
umask 077
flutter run -d <SIMULATOR_UDID> --debug --no-pub \
  --vmservice-out-file=/tmp/marionette-demo-uri
```

Flutter runnerは起動したままにします。VM Service URIは認証情報を含むため、ログや検証記録へ転記しないでください。

### 2. 接続・観測・操作する

別のターミナルで実行します。以下のkeyはexampleアプリに定義済みです。

```bash
export MARIONETTE_AGENT_SESSION=demo
marionette-agent connect "$(cat /tmp/marionette-demo-uri)"
marionette-agent snapshot

marionette-agent tap --key tap_button
marionette-agent snapshot                  # Tap countが1になったことを確認

marionette-agent fill --key text_input 'hello'
marionette-agent snapshot                  # 入力後の画面・文字数表示を確認

marionette-agent screenshot               # 一時保存先のパスを返す
marionette-agent close
```

確認後はFlutter runnerを終了し、不要になった `/tmp/marionette-demo-uri` を削除します。`close`はCLIの接続を閉じますが、Flutterアプリ自体は終了しません。

### 自分のFlutterアプリで使う

`marionette_flutter: 0.6.0`をアプリに追加し、debug起動時に `MarionetteBinding.ensureInitialized(...)` を `runApp` より前に呼びます。初期化とログ収集の例は[exampleのmain.dart](../../example/lib/main.dart)を参照してください。

型付きの入力値・チェック状態の取得などには、任意の補助パッケージ [marionette_agent_util](../../packages/marionette_agent_util/README.md)を追加し、`package:marionette_agent_util/flutter.dart`をimportして、bindingの初期化後に `registerAgentExtensions()` を呼びます。exampleは登録済みです。対応Widgetやproviderがない場合の動作は[Flutter向け追加コマンド](cli-parity.ja.md)に記載しています。

## 主なコマンド

次の例は接続済みsessionで使います。`@eN`は例示なので、直近のsnapshotに表示された対象のrefへ置き換えてください。UI操作後は新しいsnapshotを取得します。

### 観測と状態取得

```bash
marionette-agent snapshot
marionette-agent snapshot --json
marionette-agent get text --key tap_result
marionette-agent get box --key tap_button --json
marionette-agent get count --type Text --json
marionette-agent is visible --key tap_button
marionette-agent logs --json
```

snapshotは操作可能要素と可読情報の観測結果です。完全なWidgetツリーや、まだ構築されていない遅延リスト項目は含みません。

### タップ・入力・ジェスチャー

```bash
marionette-agent tap @e1
marionette-agent fill --key text_input 'こんにちは'
marionette-agent fill --key text_input ''           # 入力欄をクリア
marionette-agent swipe --key page_view left --distance 200
marionette-agent scroll --key operation_scroll_area up --distance 300
marionette-agent wait --key about_content --timeout 5000
```

`fill`は入力欄全体を置き換えます。`swipe`と`scroll`の方向は指の移動方向で、距離はFlutter論理ピクセルです。成功応答だけでは目的のページやスクロール位置への到達を保証しないため、次のsnapshotや画面で確認してください。

### 追加の検索・入力・状態取得

exampleのAdvancedタブでは補助providerを使った操作を試せます。

```bash
marionette-agent tap --key advanced_tab
marionette-agent snapshot --interactive --compact --depth 4
marionette-agent get value --key advanced_input --json
marionette-agent is enabled --key advanced_input --json
marionette-agent is checked --key advanced_checkbox --json
marionette-agent find label 'Editable' focus
marionette-agent type --key advanced_input 'hello'
marionette-agent check --key advanced_checkbox
```

ほかに `click`、`dblclick`、`press`、`keyboard`、`hover`、`select`、`drag`、`scrollintoview`、`clipboard`などを提供します。必要なproviderと制約は[追加コマンド仕様](cli-parity.ja.md)を参照してください。未観測の値や状態は、空文字やfalseと区別して返します。

## 対象の指定とrefの寿命

| 指定方法 | 用途 |
| --- | --- |
| `@e1` | 直近のsnapshotで発行された要素参照 |
| `--key <value>` | Flutter要素のkeyとの完全一致。固定手順に適しています |
| `--text <value>` | 対応する要素型のtextとの完全一致 |
| `--type <value>` | Flutter要素型との完全一致。一意な対象が必要です |
| `--identifier <value>` | 固定binding 0.6.0では未対応です |

対象指定は1つだけ使います。操作対象が0件なら `TARGET_NOT_FOUND`、複数件なら `AMBIGUOUS_TARGET` です。表示textが必ず操作用のselectorとして使えるとは限りません。

refはsessionごとに管理され、新しいsnapshot、UI操作、再接続、切断で失効します。古いrefは `STALE_REF` になります。番号を推測したり、別sessionへ流用したりせず、操作後はsnapshotを取得し直してください。

## スクリーンショットと録画

```bash
mkdir -p artifacts
marionette-agent screenshot artifacts/screen.png
marionette-agent screenshot artifacts/screen.jpg --screenshot-format jpeg

# 注釈撮影にはmapped screenshot providerが必要（exampleは登録済み）
marionette-agent snapshot
marionette-agent screenshot --annotate artifacts/annotated.png

marionette-agent record start artifacts/demo.mp4 --platform ios --device <UDID>
# ここでアプリを操作する
marionette-agent record status
marionette-agent record stop
```

保存先の親ディレクトリは事前に作成し、各撮影・録画には新しいファイル名を使います。既存ファイルは上書きしません。

録画はVM Service接続なしでも開始できます。iOS Simulatorのほか、Android、macOSディスプレイ、ChromeのWeb検証用ディスプレイ録画に対応します。プラットフォーム別の要件・録画範囲・制約は[CLIリファレンス](cli-reference.ja.md#端末画面の録画)を参照してください。

## セッションと設定

名前付きsessionで接続と観測状態を分離できます。`VM_URI_A`、`VM_URI_B`には、それぞれ起動済みアプリのVM Service URIを設定します。

```bash
marionette-agent --session alpha connect "$VM_URI_A"
marionette-agent --session beta connect "$VM_URI_B"
marionette-agent --session alpha snapshot
marionette-agent --session beta snapshot
marionette-agent session list
marionette-agent --session alpha session show
marionette-agent --session alpha close
marionette-agent --session beta close
```

| オプション・環境変数 | 用途・既定値 |
| --- | --- |
| `--session` / `MARIONETTE_AGENT_SESSION` | session名。既定は `default` |
| `--timeout` / `MARIONETTE_AGENT_TIMEOUT_MS` | キュー待ち・接続・処理を含む期限。既定は30,000ms |
| `--json` | stdoutへ構造化結果を出力 |
| `--debug` | stderrへ処理段階などの診断を追加 |
| `--config <path>` | 明示したJSON設定ファイルを読み込む |
| `MARIONETTE_AGENT_RUNTIME_DIR` | daemonのruntimeディレクトリを指定 |

共通オプションはコマンドの前後に指定できます。sessionとtimeoutの優先順位は **明示CLI > 環境変数 > 明示config > 組込み既定値** です。session名は英数字で始まる英数字・`_`・`-`の最大64文字を使います。

daemonはコマンド間で接続とrefを保持し、同じsessionの要求を直列に処理します。既定では全体が1時間無操作になると録画を確定して接続を閉じます。再開時は明示的な接続と新しいsnapshotが必要です。

## AIエージェントからの利用

エージェントには、たとえば次のように依頼できます。

> marionette-agentでexampleの入力とタップを確認してください。最初に `marionette-agent --help` と `marionette-agent skills get core` を読み、操作前後のsnapshotと画面で結果を確認してください。

インストールしたCLIに対応する操作ガイドを、その場で取得できます。

```bash
marionette-agent skills list
marionette-agent skills get core
marionette-agent skills get simulator-verify --full
```

基本の流れは **connect → snapshot → 操作 → snapshot → 結果確認 → close** です。機械処理には `--json` を指定します。通常の応答は次の包絡形式で、診断ログはstderrに分かれます。

```json
{"schemaVersion":1,"ok":true,"session":"demo","data":{},"error":null}
```

`data`にはコマンドごとの結果が入ります。`skills --json`だけは `{"success":true,"data":...}` という専用形式です。アプリ由来のsnapshotやログは未信頼コンテンツとして扱い、必要に応じて `--content-boundaries` と `--max-output` を使って識別・出力量の制限を行えます。

通信断やtimeoutでは操作結果が不明な場合があります。CLIはUI操作を自動再送しません。エラーの `outcome` とsession状態を確認し、必要なら再接続して現在の画面を観測してから次の操作を決めてください。

## ワークフロー

繰り返す手順はJSON／YAMLのworkflowとして実行できます。リポジトリルートから、同梱の例を検証・実行します。`run`にはexampleへの接続が必要です。

```bash
marionette-agent workflow validate \
  packages/marionette_agent/examples/workflows/reach-controls.yaml
marionette-agent workflow run \
  packages/marionette_agent/examples/workflows/reach-controls.yaml --json
```

workflowは最初の失敗で停止します。先行stepは実行済みの場合があるため、全体をそのまま再実行せず進捗と画面を確認してください。形式は[workflow仕様](workflow-file-spec.ja.md)、実例は[全コマンドの動作確認](../../packages/marionette_agent/examples/workflows/README.md)を参照してください。argv配列のJSONを順に実行する `batch` も提供します。

## 環境診断

```bash
marionette-agent doctor
marionette-agent doctor --json
```

接続・daemon起動なしで、ホスト環境、runtime、依存宣言、利用可能なiOS Simulatorなどを診断します。通常実行では修復を行いません。各checkの状態と `nextStep` を確認してください。

## ドキュメント

- [CLIリファレンス](cli-reference.ja.md) — 全体の構文、出力、終了コード、復旧手順
- [Flutter向け追加コマンド](cli-parity.ja.md) — 型付き観測、追加操作、差分、設定、batch
- [製品仕様](../SPEC.md) — 対象範囲とCLI契約
- [アーキテクチャ](../ARCHITECTURE.md) — CLI・daemon・backendの責務と依存関係
- [exampleアプリ](../../example/README.md) — 検証対象と起動・確認手順
- [開発ガイド](../../AGENTS.md) — 開発・検証・引き継ぎの規約
