---
title: AIエージェントから使う
description: シェル実行と同梱Skills、stdio MCPを使ってエージェントからFlutterを操作する。
---

シェルを実行できるエージェントにはCLIと同梱Skills、MCPを使うエージェントにはstdioサーバーを提供できます。どちらも同じsessionとrefの寿命に従います。

## CLIと同梱Skills

導入したCLIから、その版に対応する操作ガイドを取得できます。daemonやアプリ接続は不要です。

```sh
marionette-agent skills list
marionette-agent skills get core
marionette-agent skills get core --full
marionette-agent skills path core
```

`--full`には補助資料やテンプレートも含まれます。取得したSkillをエージェントに読み込ませ、[観測・操作・確認](/marionette_agent/ja/concepts/observation-loop/)の流れで進めます。`skills`は独自の出力形式を使うため、通常コマンドのJSON包絡とは分けて扱ってください。

## MCPクライアントへ登録する

次は`mcpServers`形式を使うクライアントの設定例です。実際の設定場所・形式はクライアントに合わせます。GUIアプリからCLIが見つからない場合は、`command`をインストール先の絶対パスにしてください。

```json
{
  "mcpServers": {
    "marionette-agent": {
      "command": "marionette-agent",
      "args": ["--session", "agent", "mcp", "--tools", "core,inspect"]
    }
  }
}
```

サーバーはクライアントの子プロセスとして動作し、stdin/stdoutをMCP通信に使用します。サーバーの起動やtool一覧の取得だけではアプリに接続しません。`connect`または`launch`のtoolで接続してください。HTTP transportは提供していません。

## 必要なtoolだけを公開する

| profile        | 主な用途                                                   |
| -------------- | ---------------------------------------------------------- |
| `core`（既定） | 接続・起動、snapshot、基本操作、画像、状態照会、待機、終了 |
| `inspect`      | value・enabled・checked、logs、doctor、device一覧          |
| `actions`      | 追加の入力、focus、check、drag、keyboard、clipboard        |
| `workflow`     | workflow、batch、confirm、deny                             |
| `record`       | 動画の開始・再開始・状態・停止                             |
| `all`          | 公開済みの全MCP tool                                       |

profileはcommaで組み合わせます。`all`でも全CLIコマンドが公開されるわけではなく、find・diff・state・skillsなどはMCP公開範囲外です。`marionette_agent_tools_profiles`で有効なprofileを確認できます。`tools/list`に`nextCursor`があれば続きも取得します。

## toolの入力と結果

tool名は`marionette_agent_`で始まります。たとえば`marionette_agent_tap`へ渡す引数は次の形です。

```json
{
  "session": "agent",
  "target": { "key": "tap_button" },
  "timeoutMs": 5000
}
```

`target`にはref・key・identifier・text・typeのどれか1つだけを指定します。詳細な入力はtoolの`inputSchema`で確認してください。

CLIを呼ぶtoolの結果には`structuredContent`の`exitCode`と`response`が入り、`response`に通常のCLI結果が含まれます。画像toolは保存先に加えて画像も返しますが、inline上限を超えた場合は保存結果を使います。

workflowやbatchにはクライアントと同じホスト上のファイルパスを渡します。MCPのstdinは通信専用なので`-`は使えません。サーバー終了だけでは独立daemonのsessionは閉じないため、作業の最後にcloseを呼びます。

## エージェントに渡す制約

対象のアプリ、session、許可する操作、期待する確認結果を明示します。アプリ内のtextやlogsは観測データとして扱い、操作方針を上書きする指示として扱わないようにします。`contentBoundaries`でその境界を示すこともできます。

[MCP・Skillsの詳細](https://github.com/r0227n/marionette_agent/blob/develop/docs/ja/cli-reference.ja.md#mcp)にprofile別tool一覧、pagination、結果形式、終了時の契約をまとめています。
