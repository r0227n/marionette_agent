# agent-browser 由来の追加オプション候補

調査日: 2026-09-09

## 調査範囲と判断基準

比較元は agent-browser の現行 README（ローカル参照コミット `72007a6788d863611b23bed0b59d0d659c638d8e`）に記載された [Snapshot Options](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#snapshot-options)、[Annotated Screenshots](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#annotated-screenshots)、[Options](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#options)、[Architecture](https://github.com/vercel-labs/agent-browser/blob/72007a6788d863611b23bed0b59d0d659c638d8e/README.md#architecture) である。

marionette_agent 側は [製品仕様](docs/SPEC.md)、[アーキテクチャ](docs/ARCHITECTURE.md)、CLI parser、snapshot、renderer、screenshot 保存、daemon の現行実装を確認した。ブラウザー固有の互換性ではなく、Flutter アプリを AI Agent が安全かつ効率よく操作する目的に有効で、現在の Marionette backend でも実現可能なものを候補にした。

優先度は次の意味で用いる。

- P0: 安全性または常駐プロセス管理に効き、早期に導入する価値が高い
- P1: AI Agent の観測効率やデバッグ効率を明確に改善する
- P2: 利便性は上がるが、代替手段があるか利用頻度が限定的

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

1. `--content-boundaries` と `--max-output` を同時に設計し、text/JSON 両形式の安全な出力契約を固める。
2. `--idle-timeout` を daemon lifecycle と session/ref 失効ルールに組み込む。
3. `--debug` と環境変数 fallback を追加し、運用時の診断と反復実行を改善する。
4. screenshot の座標倍率を信頼できる形で取得できるか調査し、可能なら `--annotate` を実装する。
5. screenshot directory / JPEG options と snapshot filter を利用シナリオに応じて追加する。

いずれも CLI の入力・出力契約を変えるため、実装時は `docs/SPEC.md`、`docs/ARCHITECTURE.md`、日本語 CLI リファレンス、todo の対象タスクを同時に更新し、実アプリを iOS Simulator で検証する。
