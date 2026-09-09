# marionette_agent — 製品仕様

状態: 初版の設計合意済み。以下は実装予定の契約。現在の実装状況は [todo.md](todo.md) を参照する。

## 目的と対象

Dart製CLIから、Marionette対応FlutterアプリをAI Agentが観測・操作できるようにする。agent-browserのsession、snapshot、短い要素参照、構造化出力という操作体系を採用する。ブラウザー固有のコマンド互換性は目的に含めない。

初版の実行ホストはmacOS、主な操作対象はiOS Simulator内の起動済みFlutterアプリ。アプリはdebug実行され、`marionette_flutter` のbindingが初期化済みで、接続可能なVM Service URIが必要。Simulatorやアプリの起動・ビルド・インストールは利用者側で行う。

MCPサーバー／クライアントの提供は対象外。`marionette_mcp` のDart接続実装をライブラリーとして利用し、VM Service経由でFlutter拡張を呼び出す。

## 用語

| 用語 | 意味 |
| --- | --- |
| session | 名前で選ぶ、1つのFlutterアプリへの接続と観測状態の単位 |
| daemon | sessionの接続と参照をコマンド間で保持するローカル常駐プロセス |
| snapshot | Marionetteから取得した操作可能要素・可読情報の観測結果。完全なWidgetツリーではない |
| ref | snapshot内の要素を指定する `@e1` 形式の短い参照 |
| selector | key・identifier・text・typeのいずれかによる明示的な対象指定 |

## CLI契約

実行名は `marionette-agent`。Dartパッケージ名は `marionette_agent` を維持し、実装時にexecutableを登録する。

```sh
marionette-agent --session demo connect 'ws://127.0.0.1:12345/token/ws'
marionette-agent --session demo snapshot
marionette-agent --session demo tap @e1
marionette-agent --session demo snapshot
marionette-agent --session demo fill @e5 'hello'
marionette-agent --session demo snapshot
marionette-agent --session demo swipe @e9 left --distance 200
marionette-agent --session demo screenshot ./screen.png
marionette-agent --session demo close
```

refは例示。実行時には直近snapshotに返されたものを使う。

### 共通オプション

| オプション | 契約 |
| --- | --- |
| `--session <name>` | 省略時は `default`。英数字で始まる英数字・`_`・`-`、最大64文字 |
| `--json` | stdoutへ1つのJSONオブジェクトを出力 |
| `--timeout <ms>` | 正の整数。既定30,000ms。待ち行列・接続・処理を含む期限 |
| `--help` / `--version` | 接続なしで利用可能 |

共通オプションはサブコマンドの前後で受け付ける。同じオプションの重複は引数エラー。対話入力は要求しない。通常出力は簡潔なテキスト、診断ログはstderr。引数不足は非ゼロで終了し、使用可能な構文を示す。

### 初版コマンド

| コマンド | 動作 |
| --- | --- |
| `connect <uri>` | 指定sessionで接続。HTTP(S)のVM Service URIもWS(S)へ正規化 |
| `session list` | sessionの名前・接続状態を一覧表示。daemon不在時は空一覧 |
| `session show` | 選択sessionの状態、秘匿済み接続先、snapshotの有効性を返す |
| `close` | 選択sessionを切断・破棄。対象不在も成功。Flutterアプリは終了しない |
| `snapshot` | 観測を更新し、要素一覧とrefを返す |
| `tap <ref>` / `tap <selector>` | 対象を1回タップ |
| `tap --x <n> --y <n>` | 明示座標を1回タップ |
| `fill <ref> <text>` / `fill <selector> <text>` | 入力欄の内容を置換。空文字でクリア |
| `swipe <ref> <direction> [--distance <n>]` | 要素を起点にスワイプ。selectorも使用可能 |
| `swipe --start-x <n> --start-y <n> --end-x <n> --end-y <n>` | 明示した始点から終点へスワイプ |
| `scroll <ref> <direction> [--distance <n>]` | スクロール領域への方向付きジェスチャー。selectorも使用可能 |
| `screenshot [path]` | PNGを保存し絶対パスを返す。省略時は一時ファイル |
| `logs` | bindingで収集されたログを取得。購読や無期限の待機はしない |

`<selector>` は `--key <value>`、`--identifier <value>`、`--text <value>`、`--type <value>` のいずれか1つ。例: `fill --key email 'a@example.com'`、`swipe --key pager left`。ref、selector、座標の混在はエラー。

scrollは初版では指定領域を既存swipe機構で操作する。directionはswipeと同じく指の移動方向であり、コンテンツの移動先や到達保証ではない。画面外要素へのscroll-toは後続とする。

### sessionの寿命と競合

- connectでdaemonを必要に応じて自動起動する。操作コマンドが未接続sessionを暗黙作成することはない。
- 同一session・同一URIへのconnectは、接続が正常なら成功。別URIへの付け替えにはcloseを先に実行する。
- sessionごとにコマンドを直列実行する。異なるsessionは独立する。同じ正規化URIを複数sessionで所有する要求は拒否する。URI別名による同一アプリの検出は保証しない。
- 通信断でsessionはdisconnectedとなりrefを失効する。明示的なconnectで復旧する。操作の自動再送はしない。
- daemon再起動で接続・snapshotを復元しない。最後のsessionを閉じたdaemonは終了する。
- タイムアウトしても送信済み操作を取り消せたとは限らない。結果不明を返し、接続を破棄して再接続と再観測を要求する。

### snapshotと要素参照

snapshotは観測世代と要素一覧を返す。各要素には取得可能なtype、text、key、identifier、bounds、visibleを含める。存在しない属性は捏造しない。テキスト出力には対象選択に必要な情報を優先し、診断プロパティ全量を載せない。

refは選択sessionの直近snapshotだけで有効。新snapshot、再接続、切断で既存refを失効する。UI操作をバックエンドへ送る直前にも全refを失効し、成功・失敗・結果不明のいずれでも再snapshotを要求する。引数検証のみの失敗は失効させない。screenshot・logs・状態照会は失効させない。

ref番号はdaemonの生存期間を通して単調増加し、sessionをまたいでも再利用しない。daemon再起動後は必ずconnectとsnapshotからやり直す。

操作直前に再観測し、保存したselectorが一意に一致し、type・識別属性・text・boundsが観測時から変化していないことを確認する。不一致はSTALE_REF、複数一致はAMBIGUOUS_TARGET。refから座標への自動フォールバックは行わない。明示selectorでも観測内の一致数を確認する。

key、identifierを優先し、text・typeはバックエンドの照合との対応を確認できる場合に使う。表示用Semanticsテキストは照合用textと同義ではない。一意に操作できるselectorを構成できない要素は情報を表示するが、操作用refを付けず理由を返す。

既存APIでは再観測と操作は原子的ではなく、観測に含まれない要素もある。その間の画面変化や同一属性の別要素への置き換えを完全には検出できない。初版はこの制約下で事前検証を行い、Flutter要素の永続IDを保証しない。

### swipeの詳細

- 要素方式と座標方式の2方式。方向はleft・right・up・down。
- 距離は有限の正数、既定200。座標は有限の非負数。単位はFlutterの論理ピクセルであり、画像の物理ピクセルとは区別する。
- 座標方式は4座標をすべて必須とし、同一の始点・終点は拒否する。要素方式のオプションとの混在も拒否する。
- 速度・継続時間・慣性の指定、iOSホーム操作などのシステムジェスチャーは対象外。
- 成功はバックエンドのジェスチャー処理完了。ページ切替などの結果は次のsnapshotで確認する。

### 出力と終了コード

JSONは成功・失敗とも以下の包絡形式。schemaVersionは初版で1。session非依存コマンドではsessionはnull。dataとerrorの一方だけを非nullとする。help/versionもJSONモードでは同じ包絡形式を使う。

```json
{"schemaVersion":1,"ok":true,"session":"demo","data":{"requiresSnapshot":true},"error":null}
```

```json
{"schemaVersion":1,"ok":false,"session":"demo","data":null,"error":{"code":"STALE_REF","message":"Target changed","hint":"Run snapshot again","outcome":"not_sent"}}
```

outcomeはnot_sent・failed・unknown。送信後の通信断・タイムアウトを未実行として扱わない。

| 終了コード | エラー分類と代表code |
| --- | --- |
| 0 | 成功 |
| 2 | 引数: INVALID_ARGUMENT |
| 3 | 接続・session: NOT_CONNECTED、SESSION_CONFLICT、CONNECTION_LOST |
| 4 | 対象: TARGET_NOT_FOUND、AMBIGUOUS_TARGET、STALE_REF、UNRESOLVABLE_TARGET |
| 5 | 期限超過: TIMEOUT |
| 6 | 機能不足: UNSUPPORTED_CAPABILITY |
| 1 | その他: BACKEND_ERROR、IO_ERROR、INTERNAL_ERROR |

screenshotのdataはpaths配列。複数画像は連番で保存し、既存ファイルの上書きは拒否する。画像が空なら失敗。logsは返された範囲を正規化し、収集未設定と0件を識別できない場合、その制約を伝える。URIの認証部分や入力文字列を診断ログへ出力しない。

## 初版の完了条件

1. macOSからiOS Simulatorに接続し、別々のCLIプロセスでsnapshot→tap／fill／swipe→snapshotが成立する。
2. 2つのsessionの接続・ref・切断が分離され、同一sessionの並行要求が直列化される。
3. 古いref、曖昧な対象、通信断、timeoutが規定のJSONと終了コードになり、操作が自動再送されない。
4. PageViewの切替とDismissibleのdismissをswipeで確認し、座標方式もSimulatorで検証する。
5. scroll、PNG保存、ログ取得が動作し、別モデルが共通基盤の契約を変更せず実装できる。
6. 自動テストとSimulator検証の結果・環境をtodoに記録する。未検証項目を完了扱いにしない。

## 後続範囲

Android／実機／他ホストOS、アプリ起動管理、録画、独自拡張、hot reload/restart、double-tap／long-press／pinch、キー入力、scroll-to、session永続復元。MCP対応は今回の計画に含めない。
