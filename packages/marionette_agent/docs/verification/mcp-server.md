# stdio MCPサーバーの検証

2026-09-20、コードcommit `d348c3c411deabd1e7044f7779f489a01157ea96`を検証した。以下は当該commitに対する初回検証の記録。

## 環境と経路

- macOS 26.5.2（arm64）、Dart 3.13.2、Flutter 3.47.2。
- `dart_mcp 0.5.2`、`marionette_mcp 0.6.0`、exampleの`marionette_flutter 0.6.0`。
- 専用iPhone 17 Pro／iOS 26.2、UDID `5CEB8FEE-A5D6-4767-BDA0-D8F7AA523D3D`。
- SDKクライアント → 製品CLIのMCP stdio → 同じ製品CLIの子process → 専用runtimeのdaemon → example。
- Dart sourceとコンパイル済み実行ファイルの両方を、fixtureをリセットして検証。protocolVersionは2025-11-25。

## 結果

format変更なし、analyze指摘なし、全332テスト成功（MCP専用10テストを含む）。既存queueテストのblockerが並列実行中のcold CLI起動に先行して期限切れとなったため、検証対象の200msは維持し、blockerの期限だけ2秒から10秒へ延長した。修正後、通常の並列度で全体が成功した。

MCP自動テストでは初期化と旧protocol対応、profile合成／拒否、20件pagination、未知tool、型付き入力、literalの改行／日本語／option風文字列、session、stale／ambiguous／timeout、再送しないこと、PNG/JPEGと既存file拒否、EOF、所有CLIの回収、壊れた子process応答のunknown分類を確認した。

Simulatorの[再現スクリプト](../../integration_test/mcp_smoke.dart)は両実行形態で次を満たした。

| 操作 | 期待結果 | 実際 |
| --- | --- | --- |
| initialize、tools/list | SDKとの交渉と全profileの列挙 | 2025-11-25、52 tools |
| connect → snapshot | 初期状態を取得 | Tap count: 0、未入力、Current page: 1 |
| tap_buttonのrefをtap | 1回だけ操作 | Tap count: 1 |
| 同じrefを再利用 | staleを送信前に拒否 | 終了4、STALE_REF、not_sent、countは1のまま |
| text_inputへfill | 指定文字列へ置換 | MCP verified、12 characters |
| (20,80)をtap | キーボードを閉じる | 入力内容とcountを維持 |
| page_viewをleft／250pxでswipe | 次のページへ遷移 | Page 2、Current page: 2 |
| screenshot PNG／JPEG | file保存とMCP画像の一致 | ImageContent各1件、保存bytesと一致 |
| 別CLI processのsnapshot | 同じruntime/sessionを参照 | count 1、12文字、page 2 |
| close → stdin EOF | sessionとMCPを終了 | 両方終了0、MCP stderr空、daemon metadata消失 |

200pxのswipeでは当該fixtureのpageが1のままだったため、既存の受入シナリオと同じ250pxを使用した。ジェスチャーの成功応答だけで判定せず、snapshotと画像でpage 2を確認している。

画像は`01-before.png`（初期状態）、`02-filled.png`（tap／fill後）、`03-swiped.png`（page 2）、`04-swiped.jpg`（JPEG）の4点を開いて確認した。MCPの保存結果と同じ画像をDraft PRへ添付する。秘匿済みの各tool入力・structuredContent・画像件数は、再現スクリプトの出力先`evidence/transcript.json`に保存する。認証URIとraw runnerログは添付しない。

所有するMCP／CLI／daemon／Flutter runner／exampleが終了したことを確認し、専用Simulatorをshutdown、URI fileを削除した。他のSimulatorやsessionは操作していない。

## 再現

1. このブランチでCLIとexampleの依存を取得する。専用Simulatorを選び、exampleをdebugで起動する。fixtureは再起動してTap count 0、未入力、Page 1に戻す。
2. 新しい短い私有directoryを用意し、Flutter runnerの`--vmservice-out-file`をその`uri`へ指定する。rawログは画像用directoryから分離する。認証URIを表示・転記しない。
3. `packages/marionette_agent`を作業directoryとし、環境変数`MARIONETTE_TEST_VM_URI_FILE`へそのURI fileの絶対path、`MARIONETTE_TEST_OUTPUT`へ新しい検証出力先の絶対pathを指定して`integration_test/mcp_smoke.dart`をDartで実行する。runtime pathは80 UTF-8 bytes以内とする。
4. 成功時は52 tools、tap 0→1、12文字、page 1→2、画像一致、session共有、EOF／daemon cleanupのPASSが表示される。出力先の`evidence`内の4画像を開いて表示を照合する。
5. compiled版は同ブランチの`bin/marionette_agent.dart`をコンパイルし、`MARIONETTE_TEST_MCP_EXECUTABLE`へ実行ファイルの絶対pathを追加する。exampleを再起動し、別の空出力先で同じスクリプトを実行する。
6. スクリプトはcloseとMCP終了までを行う。Flutter runnerは`q`で終了し、アプリ停止・専用Simulatorのshutdownを確認する。不要になったURI fileを削除する。

手動のMCPクライアント登録とtool入力は[日本語CLIリファレンス](../../../../docs/ja/cli-reference.ja.md#mcp)を参照する。既定coreは17件（操作16＋profiles）、allは52件。実行形態を切り替えるときは毎回新しいruntimeを使用する。

## 制限と人間確認

HTTP transport／cancellationは未対応。SDKの通信断は、すでに実行されたUI操作の取消しを保証しない。MCP終了だけでは既存sessionを破棄せず、明示closeが必要。今回の実環境受入はiOS Simulator上のcore操作であり、全platform／全52toolの実環境網羅を意味しない。既存CLIのプラットフォーム検証を置き換えない。

- [ ] 人間がMCPクライアントから上記操作と画像を確認した

## 参照

- [dart_mcp 0.5.2](https://pub.dev/packages/dart_mcp/versions/0.5.2)
- [MCP stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- 参考実装: 隣接agent-browserの`cli/src/mcp.rs`（stdio、profile、typed tool、CLIの再利用）。隣接repoへの変更や配布依存は追加していない。
