# agent-browser 由来の追加コマンド・オプション候補

調査日: 2026-09-09（全コマンド再確認: 2026-09-10）

## 調査範囲と判断基準

比較元は agent-browser の現行 README（ローカル参照コミット `72007a6788d863611b23bed0b59d0d659c638d8e`）に記載された [Get Info](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#get-info)、[Find Elements](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#find-elements-semantic-locators)、[Snapshot Options](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#snapshot-options)、[Annotated Screenshots](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#annotated-screenshots)、[Options](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#options)、[Architecture](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#architecture) である。

marionette_agent 側は [製品仕様](docs/SPEC.md)、[アーキテクチャ](docs/ARCHITECTURE.md)、CLI parser、snapshot、renderer、screenshot 保存、daemon の現行実装を確認した。ブラウザー固有の互換性ではなく、Flutter アプリを AI Agent が安全かつ効率よく操作する目的に有効で、現在の Marionette backend でも実現可能なものを候補にした。

優先度は次の意味で用いる。

- P0: 安全性または常駐プロセス管理に効き、早期に導入する価値が高い
- P1: AI Agent の観測効率やデバッグ効率を明確に改善する
- P2: 利便性は上がるが、代替手段があるか利用頻度が限定的

## 実装を推奨するコマンド

### P0: 単独 `wait`

`wait` は最優先で追加を推奨する。現状は workflow step として `state: exists|gone`、step timeout、poll interval を実装済みだが、単独コマンドでは使えない。AI Agent が `tap` 後の非同期な画面遷移を待ってから `snapshot` する基本フローで必要になる。

最初の契約は、既存 workflow 実装を共通化して次に限定する。

```text
wait <selector> [--state exists|gone] [--poll-interval <ms>]
```

- `<selector>` は既存どおり `--key`、`--identifier`、`--text`、`--type` のいずれか一つとし、ref は受け付けない。待機中に対象が変化する用途で stale ref を持ち込まないためである。
- `exists` は一意かつ `visible != false` を成功条件とし、複数一致は既存workflowと同じく `AMBIGUOUS_TARGET` にする。`gone` は一致なしを成功条件とし、一つ以上残っている間は件数にかかわらず待機を続ける。
- コマンド全体の期限は共通 `--timeout` を使う。別の `--timeout` をコマンド内へ重複定義しない。
- 観測だけを再試行し、tap/fill/swipe などの UI 操作は再送しない。
- 成功しても snapshot/ref は新規発行しない。後続操作前に `snapshot` を実行する流れを案内する。

agent-browser の `wait <ms>` は shell の待機で代替でき、session queue を理由なく占有するため優先度は低い。`--url`、`--load`、`--fn` は Web/DOM 固有なので不要である。`--text` は substring 検索として移植せず、まず既存の exact text selector を使う。

### P1: `get`

`get` は追加を推奨する。現行の `snapshot` に text、bounds、visible などは含まれるが、単一の確認にも全要素を再出力する。agent-browser の `get` と同様に対象と取得項目を明示できれば、出力量を抑えつつ操作結果を検証できる。

最初に実装する価値があるのは、現行 `ElementInfo` だけで正確に返せる次の形式である。

| コマンド案 | 用途 | 契約上の注意 |
| --- | --- | --- |
| `get text <ref|selector>` | 表示テキストを取得する | 対象は一意でなければならない。値が観測されていなければ空文字を捏造せず `value: null` とする。read-only なので ref を失効させない。 |
| `get box <ref|selector>` | Flutter 論理座標の bounds を取得する | screenshot の物理 pixel と同じ座標だと主張しない。bounds がない場合を構造化して返す。 |
| `get count <selector>` | selector に一致する要素数を取得する | このコマンドだけは 0 件・複数件を正常結果として扱う。曖昧性の調査に使うため ref は受け付けず、操作用の一意性検証を流用しない。 |
| `get attr <ref|selector> <text|key|identifier|type|visible|bounds>` | snapshot が保持する既知属性を取得する | 任意の backend property 名ではなく allowlist に限定する。`get text` / `get box` と重複するため、統一APIとして採用する場合だけ追加する。 |

`get value` は入力結果の検証に特に有用だが、固定している binding 0.6.0 の `getInteractiveElements()` と現行 `ElementInfo` は input value を text と別の属性として保証していない。text を value と見なさず、上流 capability と型付き `ElementInfo.value` を追加できた時点で実装する。`get html`、`get styles`、`get title`、`get url`、`get cdp-url` は Web/DOM/CDP 固有なので不要である。

### P1（能力追加）: semantic `find`

semantic find の能力は必要だが、agent-browser の構文を丸ごと移植することは推奨しない。

現行の `tap`、`fill`、`swipe`、`scroll` は既に `--key`、`--identifier`、`--text`、`--type` で対象を指定できる。この範囲の `find text ... click/fill` を追加すると、同じ操作への二つ目の入口になり、target 解決と ref 失効の契約が重複する。代わりに Flutter Semantics / Marionette が信頼できる形で提供できる属性を `SelectorKind` に追加し、既存の全コマンドから共通利用できるようにする。

追加を検討すべき selector は次のとおり。

- Semantics の role 相当
- label
- hint / placeholder 相当
- value（入力値を読み取る用途を含む）
- tooltip

`find` という独立コマンドを置く場合は、`find --label <value>` のような read-only の検索に限定し、一致した全要素と件数を返す。これは `snapshot` filter と統合してもよい。

agent-browser の `find first`、`find last`、`find nth` による click/fill は追加しない。複数一致から位置で操作対象を選ぶ方式は、marionette_agent の「明示 selector でも一意性を確認し、曖昧な対象を拒否する」という安全契約を弱める。どうしても必要になった場合は selector の一部として明示的な index 契約をSPECで設計し、UI変化に対する stale 判定を用意してから導入する。

### P1: `is visible`、条件付きで `is enabled|checked`

状態確認は操作の前提条件や結果を小さいJSONで検証できるため追加価値がある。

- `is visible <ref|selector>` は現行 `ElementInfo.visible` で実装できる。ただし backend が `null` を返した場合は `false` に丸めず、`known: false` を返す。
- `is enabled` と `is checked` は現行 `ElementInfo` に情報がない。Marionette binding が Semantics の enabled/checked state を型付きで返せるようになってから追加する。
- 0件や複数件を単純な `false` にせず、それぞれ `TARGET_NOT_FOUND`、`AMBIGUOUS_TARGET` とする。対象解決の問題と状態値を混同しない。

### P1: `close --all`

複数sessionを一括破棄し daemon を確実に終了する運用コマンドとして有用である。全sessionの新規受付を止め、各queueの実行中操作を途中で「未送信」と見なさず、安全に完了または期限切れにしてから切断する必要がある。部分失敗時の session ごとの結果をJSONで返す契約を先に決める。

### P1（上流拡張後）: `scrollintoview`

画面外要素を操作可能にするため重要であり、現在の方向付き `scroll` よりAgent向けである。ただし現行 snapshot は画面外を含む完全な Widget tree ではなく、backend に対象までスクロールする primitive もない。SPECで既に将来範囲とされているため、上流bindingで一意な対象解決とscroll-toを提供できた時点で実装する。探索中にUI操作を繰り返す実装にする場合も、各gestureの結果不明性と再送禁止を守る必要がある。

### P1: `doctor`

agent-browser の `doctor` と同様に、Agent自身が環境問題を切り分けられる診断コマンドは有用である。接続不要かつ原則read-onlyで、少なくとも次をJSON化する。

- host OSとDart runtimeがサポート範囲内か
- runtime directoryの所有者・permission・socket path長
- 稼働daemonのprotocol versionと応答可否
- 固定した `marionette_mcp` / binding versionと必要capability
- 利用可能なiOS Simulatorと、指定された場合だけVM Service URIへの接続probe

通常の `doctor` でsocket削除、daemon停止、package再導入を自動実行しない。修復操作が必要なら将来 `doctor --fix` として個別の実行内容を明示し、通常診断と分ける。認証付きURIは完全表示しない。

### P1（上流拡張後）: `a11y audit`

FlutterアプリをAgentが操作できることと、支援技術から正しく利用できることは別なので、Semanticsの欠落・曖昧なlabel・小さいtap target・無効なstate組み合わせを検出する監査は有用である。ただし現行 `inspect()` は完全なSemantics treeではない。必要属性と親子関係をbindingが返せるようにしてから、rule ID、severity、対象属性、refまたは安定selectorを構造化して返す。Webのaxe ruleを名前だけ流用しない。

## 全コマンド群の棚卸し

agent-browser README の Commands をカテゴリ単位で確認した結果は次のとおり。

| agent-browser の機能 | 判定 | marionette_agent での扱い |
| --- | --- | --- |
| `open` / navigation | 不要 | Simulatorとアプリの起動管理は現行スコープ外。接続は `connect <uri>` が担当する。 |
| `read` | 代替済み | アプリ内の観測は `snapshot` が担当する。URL fetch、Markdown、llms.txt はWeb固有。 |
| `click` | 代替済み | `tap` が担当する。`--new-tab` は不要。 |
| `fill` | 実装済み | 現行の置換入力を維持する。 |
| `type` / `press` / `keyboard` / `keydown` / `keyup` / `focus` | 条件付き候補 | IME、submit、shortcut、focus遷移のテストには有用。ただし現行bindingは実キーイベントを保証せず、SPECでもキー入力は将来範囲。上流primitive追加後にP1として再検討する。 |
| `dblclick` | 条件付き候補 | Flutterではdouble-tap相当。初版対象外でbackend primitiveもないためP2。long-pressも同じgesture拡張として設計する。 |
| `hover` / mouse | 不要 | 初版のiOS Simulator操作はtouch中心。pointer/desktop対応を対象にするとき再検討する。 |
| `select` / `check` / `uncheck` | 条件付き候補 | 現在は `tap` で操作できるが冪等ではない。selected/checked/enabled状態をbindingが返せるようになれば、状態確認付きの専用操作としてP2。 |
| `scroll` | 実装済み | 方向付きgestureとして実装済み。到達保証はない。 |
| `scrollintoview` | 推奨（上流待ち） | 画面外対象の操作に必要。前節のとおりP1。 |
| `drag` | 条件付き候補 | reorder、slider、drag-and-dropのテストに有用。durationと移動経路を持つbackend primitiveが必要なためP2。 |
| `upload` / `pdf` | 不要 | DOM file inputとWeb page PDF化に対応する概念がない。Flutter側のfile picker注入は別機能として設計する。 |
| `screenshot` | 実装済み＋拡張推奨 | 保存は実装済み。annotate、directory、JPEG関連は下記オプション候補。 |
| `snapshot` | 実装済み＋拡張推奨 | filterと出力制限を候補とする。tree前提のdepth/compactは不要。 |
| `eval` | 不要 | 任意Dart/Flutterコード実行は安全性と配布契約を壊す。MCP/独自拡張も対象外。 |
| `connect` / `close` | 実装済み＋拡張推奨 | VM Service向けに実装済み。`close --all` を候補とする。 |
| `session list` / current session / info | 実装済み相当 | `session list` と `session show` が担当する。worktree由来の `session id` は環境変数fallback導入後に必要性を再評価する。 |
| `get` | 推奨 | text、box、countをP1。valueは上流属性追加後。 |
| `is` | 一部推奨 | visibleをP1。enabled/checkedは上流属性追加後。 |
| `find` | 能力追加を推奨 | 重複コマンドより共通selector語彙を拡張する。位置指定actionは不採用。 |
| `wait` | 推奨 | workflow専用実装を共通化し、単独コマンドをP0。 |
| `batch` | 代替済み | `workflow run` が一括validation、同一queue、途中失敗progressを含む上位機能。別構文は追加しない。 |
| `clipboard` | 条件付き候補 | system clipboardの読み書きは便利だが、秘密情報漏えいとSimulator境界の仕様が必要。アプリ操作の中核ではないためP2以下。 |
| browser settings / cookies / storage / network | 不要 | Web/Chromium固有。位置情報、offline等のSimulator制御は将来、アプリ起動管理とは別のhost adapterとして検討する。 |
| tabs / windows / frames | 不要 | 1 session = 1 Flutter app接続であり、DOM browsing contextは存在しない。複数アプリは既存sessionで分離する。 |
| dialogs | 代替済み | Flutter dialogも通常のsnapshot要素として明示的に操作する。JavaScript dialogの自動処理は不要。 |
| back / forward / reload / pushstate | 当面不要 | Web navigation操作は不要。Flutter Navigatorのbackやhot reload/restartは異なる機能で、後者は現SPECの対象外。アプリ内backが必要ならSemanticsでback buttonを明示操作する。 |
| `diff snapshot` | 条件付き候補 | UI変化の要約に有用。ただしref番号を除いた正規化、属性順、消滅/追加/変更のschemaが必要。workflow結果検証の改善としてP2。 |
| `diff screenshot` | 条件付き候補 | visual regressionには有用だが、CLI外の画像比較でも代替可能。閾値、scale、向きの正規化が必要なためP2。 |
| trace / profiler / record | 当面不要 | Chrome traceは利用不可。Flutter DevTools/ETTraceや`simctl`録画との責務分担が必要で、録画は現SPECの対象外。 |
| console / errors | 一部代替済み | `logs` が担当する。収集レベル、clear、例外分類はbinding capabilityが増えたら拡張する。 |
| `highlight` | 条件付き候補 | 対象確認にはannotated screenshotの方が非侵襲的。アプリUIへoverlayを注入する必要があるため優先しない。 |
| `a11y audit` | 推奨（上流待ち） | Flutter Semantics向けの独自ruleとしてP1。完全なSemantics属性・階層が必要。 |
| install / upgrade | 不要 | Dart packageの導入・更新はpubや配布手段の責務。CLI自身からpackage managerを実行しない。 |
| `doctor` | 推奨 | runtime、daemon、protocol、binding、Simulator、任意接続probeを診断するP1候補。 |
| skills | 不要 | Codex等のAgent環境が管理する責務で、製品CLIに同梱する必然性がない。 |
| state / auth / vault | 不要 | session永続復元は対象外。認証入力はworkflowのsensitive inputで扱い、保存機能は別途security designが必要。 |
| stream / dashboard / chat / WebMCP / React / plugin | 不要 | browser固有、自然言語実行、MCP、拡張pluginは現プロジェクトの対象外。 |

## 実装を推奨するオプション

| 優先度 | 候補 | 推奨理由 | marionette_agent での契約案・注意点 |
| --- | --- | --- | --- |
| P0 | `--content-boundaries` | agent-browser はページ由来の出力を境界マーカーで囲み、未信頼コンテンツと CLI 自身の出力を区別する。Flutter の表示テキストやログにも prompt injection 相当の文字列が入り得るため、同じ防御が有効。 | text 出力のうち `snapshot` と `logs` のアプリ由来部分だけを、固定かつ衝突しにくい開始・終了マーカーで囲む。JSON は文字列へマーカーを混入せず、必要なら envelope に `contentBoundary` メタデータを追加する。入力文字列や認証 URI を診断へ出さない既存契約は維持する。 |
| P0 | `--max-output <chars>` | agent-browser は context flooding 防止のため出力長上限を提供する。要素数の多い snapshot と大量ログは marionette_agent でもコンテキストを圧迫し得る。 | 生の JSON 文字列を途中で切らない。renderer の text 出力と、JSON の `elements` / `entries` を項目境界で制限し、`truncated: true`、省略件数、元件数を構造化して返す。ref の採番と snapshot generation は全観測結果に対して確定し、省略された ref を推測させない。画像 base64 は対象外とし、IPC の 64 MiB 上限とは別契約にする。 |
| P0 | `--idle-timeout <duration>` | agent-browser daemon は既定 1 時間の無操作終了を持ち、呼び出し元が `close` し忘れても常駐プロセスを残し続けない。marionette_agent は最後の session を `close` した場合だけ終了するため、異常終了した利用側が session を残す可能性がある。 | daemon 全体の無操作時間として実装し、実行中・queue 待ち中は終了しない。終了時は接続を破棄し ref を失効させ、次回は明示 `connect` が必要と文書化する。`10s` / `3m` / raw ms などを受け付けるかは別途仕様化し、`0` で無効化できるようにする。設定値の異なる同時 CLI 呼び出しをどう扱うかも daemon 起動契約で固定する。 |
| P1 | `screenshot --annotate` | agent-browser は screenshot 上の番号と snapshot ref を対応させ、視覚情報と操作対象を結び付ける。モバイル UI は配置の確認が重要なので効果が大きい。 | 直近の有効な snapshot を必須とし、操作可能 ref の bounds に `@eN` ラベルを合成する。Flutter の論理座標と screenshot の物理 pixel の倍率・向き・複数画像の対応を backend 境界で取得または検証できない限り、誤った注釈を出さず `UNSUPPORTED_CAPABILITY` にする。注釈生成自体は CLI 側で行い、元画像を上書きしない。 |
| P1 | `snapshot --selector <selector>` 相当 | agent-browser は snapshot を CSS selector 配下へ絞れる。Flutter では CSS は使えないが、大画面の一部だけを観測できれば出力量を減らし、曖昧性の調査に役立つ。 | 既存 selector 語彙に合わせて `snapshot --key/--identifier/--text/--type` のいずれか一つを受け付ける案が自然。ただし現行 backend は完全な Widget tree を返さず、子孫範囲を表現できないため、初版は「一致要素だけを返す filter」と明記する。将来 backend が階層を返せる場合のみ scope semantics を追加する。新 snapshot なので従来どおり既存 ref はすべて失効させる。 |
| P1 | `--debug` | agent-browser は opt-in の debug 出力を提供する。接続、daemon 起動、backend capability、timeout の切り分けが必要な CLI でも有用。 | stderr のみへ、request ID、session 名、処理段階、経過時間、正規化済み error code を出す。VM Service URI の認証情報、fill 入力、アプリ表示テキスト、stack trace は既定で出さない。`--json` の stdout envelope を汚さない。 |
| P2 | `--screenshot-dir <path>` | agent-browser は screenshot の既定保存先を指定できる。連続取得や CI artifact の整理が楽になる。 | `screenshot` に明示 path があればそちらを優先し、省略時だけ指定 directory に衝突しない名前を生成する。現行の排他的作成、symlink 拒否、絶対 path 返却を維持する。 |
| P2 | `--screenshot-format png|jpeg` | agent-browser は PNG/JPEG を選択できる。JPEG は視覚確認用 screenshot のファイル容量を減らせる。 | backend から受け取る PNG を CLI 境界で変換する。既定は lossless な `png` のままにし、拡張子と format の矛盾は引数エラーにする。比較・証跡用途では PNG を推奨する。 |
| P2 | `--screenshot-quality <0-100>` | agent-browser は JPEG quality を指定できる。CI artifact や Agent へ渡す画像サイズを調整できる。 | `--screenshot-format jpeg` のときだけ有効にし、単独指定は `INVALID_ARGUMENT`。画像変換も `--timeout` の絶対期限に含める。 |
| P2 | `--session` / `--timeout` の環境変数 fallback | agent-browser は `AGENT_BROWSER_SESSION` や `AGENT_BROWSER_IDLE_TIMEOUT_MS` などを持ち、繰り返す共通値を毎回渡さずに済む。marionette_agent は runtime directory だけ環境変数対応で、session と timeout は CLI 固定値である。 | `MARIONETTE_AGENT_SESSION`、`MARIONETTE_AGENT_TIMEOUT_MS` を候補とする。優先順は「明示 CLI > 環境変数 > 既定値」。不正値を黙って既定値へ戻さず `INVALID_ARGUMENT` にする。秘密値は対象にしない。 |

## 今は実装を推奨しないもの

| agent-browser のオプション | 判断 |
| --- | --- |
| `snapshot --interactive` | marionette_agent の `inspect()` は既に interactive / readable elements を対象にしており、同じ意味の切替を追加しても差が小さい。将来、完全な Widget tree を snapshot に含める場合に再検討する。 |
| `snapshot --compact`, `--depth` | 現行 snapshot は tree ではなく平坦な要素一覧なので意味を定義できない。 |
| `--restore`, `--state`, `--profile` | SPEC は daemon 再起動後の session 復元を対象外としている。VM Service 接続と ref を安全に復元できず、ブラウザーの storage state と同等ではない。 |
| `--device`, `--provider`, `--engine`, `--headed`, `--executable-path`, `--cdp`, `--auto-connect` | Simulator / アプリの起動管理は現行スコープ外で、接続先は利用者が渡す VM Service URI である。 |
| `--headers`, `--proxy`, `--user-agent`, `--ignore-https-errors`, `--allow-file-access`, `--color-scheme`, `--webgpu`, `--extension`, `--init-script` | Web/Chromium 固有で、Marionette 対応 Flutter アプリを操作する backend には対応概念がない。 |
| `--allowed-domains` | Web navigation と subresource 通信を閉じ込める機能であり、Flutter アプリ自体のネットワーク通信を marionette_agent から確実に制御できない。名前だけ似た不完全な防御は追加しない。 |
| `--action-policy`, `--confirm-actions`, `--confirm-interactive` | 方向性は有用だが、現行の tap/fill/swipe から「破壊的操作」を静的に分類できず、CLI は対話入力を要求しない契約である。先に workflow/action の policy 語彙、非対話 approval token、拒否時の outcome を設計すべきで、単純な option 移植は推奨しない。 |
| `--config <path>` | 候補を一括設定できるほど option がまだ多くない。まず環境変数 fallback を導入し、設定項目が増えた時点で schema、探索順、権限、未知 key の扱いを設計する。 |
| `--quiet`, `--verbose`, `--model` | agent-browser の AI chat 用であり、自然言語 chat を提供しない marionette_agent には不要。 |

## 推奨する導入順

1. workflowのwait loopを共通化し、単独 `wait` を追加する。
2. `get text`、`get box`、`get count` と `is visible` のread-only契約を追加する。
3. `--content-boundaries` と `--max-output` を同時に設計し、text/JSON両形式の安全な出力契約を固める。
4. `--idle-timeout` と `close --all` をdaemon lifecycleとsession/ref失効ルールに組み込む。
5. `--debug` と環境変数fallbackを追加し、運用時の診断と反復実行を改善する。
6. read-onlyの `doctor` を追加し、環境・daemon・bindingの自己診断を可能にする。
7. upstreamで取得可能なSemantics属性を調査し、selector語彙を増やす。独立した `find` はread-only filterが必要かを見て判断する。
8. `scrollintoview` と `a11y audit` に必要な上流primitive・Semantics tree・安全契約を設計する。
9. screenshotの座標倍率を信頼できる形で取得できるか調査し、可能なら `--annotate` を実装する。
10. screenshot directory / JPEG options、snapshot filter、diffを利用シナリオに応じて追加する。

いずれも CLI の入力・出力契約を変えるため、実装時は `docs/SPEC.md`、`docs/ARCHITECTURE.md`、日本語 CLI リファレンス、todo の対象タスクを同時に更新し、実アプリを iOS Simulator で検証する。
