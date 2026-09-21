# CLI実行の詳細

[English](../cli-reference.md) · [日本語の目次](README.md)

基本構文、コマンド一覧、導入例は[公開リファレンス](https://r0227n.github.io/marionette_agent/ja/reference/commands/)へ集約しました。本書はスクリプト・MCPクライアント・厳密な出力処理を実装するための補足です。追加操作は[providerと操作の制約](cli-parity.ja.md)、workflowは[ファイル仕様](workflow-file-spec.ja.md)を参照してください。

<a id="arguments"></a>
## 引数と診断

共通オプションの重複・値欠損は引数エラーです。`--`以降は位置引数として扱い、オプションとして再解釈しません。sessionとtimeoutの優先順位は明示CLI、環境変数、明示config、組込み既定値です。選択された値だけを検証し、不正な値を既定値へ戻しません。CLIで上書きした環境値は不正でも無視します。

構文エラーでも有効なsessionとJSON指定を回復します。不正なsession、session非依存コマンド、`close --all`の応答は`session:null`です。timeoutは読込・起動・queue待ちを含む絶対期限で、timeout値は正整数かつDuration/DateTimeの表現範囲内でなければなりません。

`--debug`は要求単位で有効です。段階は`cliParsed`、`runtimePrepare`、`daemonOpen`、`daemonStart`、`daemonReady`、`requestSend`、`daemonDispatch`、`sessionQueue`、`commandExecute`、`daemonResult`、`cliResult`のうち到達したものを記録します。`elapsedMs`は各区間の開始からの時間で、daemon側の診断は応答受信時に表示します。request ID、session、段階、時間、正規化error codeをstderrへ出し、認証URI・入力値・selector値・アプリtext・stack traceは追加診断へ出しません。session名に秘密値を使わないでください。

<a id="output"></a>
## 未信頼コンテンツと出力予算

`--content-boundaries`のtext境界はsnapshotの要素列とlogsのentryだけを囲みます。nonceは要求ごとの128bit random hexです。見出し・hint・件数・診断は境界外です。アプリの文字列を安全な指示へ変換する機能ではありません。

JSONは文字列を変更せず、対象dataへ`contentBoundary:{nonce,source}`を追加します。sourceは`snapshot`または`logs`です。`--max-output`指定時は`truncated`、`originalCount`、`omittedCount`を常に追加します。

予算はUnicode code point数です。textでは要素行またはJSON化したlog entry、JSONでは各項目のcompact JSONを数え、項目間の改行・commaも含めます。JSON包絡、配列括弧、見出し、境界と件数metadataは予算外です。完全な項目を先頭から採用し、次が収まらなければ残りを省略します。quote・escapeも数えるため、textとJSONの件数は異なる場合があります。

一意性判定とref採番は全観測に対して行い、その後filter、出力予算の順で制限します。省略refは使用できません。filter指定時の`filter:{kind,value,matchedCount,totalCount}`は予算外で、`originalCount`はfilter後の件数です。filter自体はtruncationではありません。snapshotのtext/identifier filterは観測属性を比較し、そのselectorで操作できることは保証しません。

workflowの`finalSnapshot`にも予算を適用します。画像、他コマンド、stderrやIPC frameの64 MiB上限は対象外です。get/isは公開refを更新せず、欠損text/boundsはnull、実際の空文字・ゼロはそのまま返します。`get count`は観測候補数であり、操作可能数ではありません。

<a id="lifetime"></a>
## daemonと終了処理

idle期限はdaemon起動時に固定されます。省略した要求は既存値を継承し、異なる値の明示は送信前に拒否します。`0`は自動終了を無効にします。全sessionをcloseしてから、新しい値で起動してください。実行・queue待ち・応答配送中はidle終了せず、health probeは期限を延長しません。録画だけの継続はidle終了の対象です。

終了時には録画を確定し、session・ref・socket・lockを解放します。`launch`が所有するrunnerは回収し、`connect`した外部アプリは残します。次回は明示的な接続とsnapshotが必要です。

選択sessionのcloseで録画確定が期限切れになった場合はsessionを保持し、`record status`で確認してから再度closeできます。切断自体の失敗・期限切れではsessionとrefを破棄します。`close --all`は録画確定の期限切れでもdaemon終了へ進みます。session別結果は成功時`data.sessions`、部分失敗時`error.details.sessions`へ名前順で返します。期限超過があれば終了5、他の失敗は1、全成功は0です。詳細は[SPEC](SPEC.ja.md#close---all)を参照してください。

<a id="doctor"></a>
## doctorの判定

通常は読み取りだけでhost、runtime所有者・0700・path長、daemon protocol、固定依存、iOS Simulatorを確認します。未作成runtimeは正常な未実施扱いです。`--probe-uri`を明示した場合だけ専用接続でアプリを調べ、終了時に解放します。実応答がなければbinding versionを推測しません。

checkは`success`、`failure`、`unknown`、`skipped`です。診断を返せれば`ok:true`でも、failure/unknownがあれば`data.exitCode`とprocess終了値は1です。doctor内のtimeoutはunknown/終了1、引数エラーは終了2です。全体期限を過ぎた未着手checkもunknownとなり、daemon handshake待ちは最大1秒です。

`--quick`はhost/runtime/daemonだけ、`--offline`はVM probeを省略します。`--fix`は自分が所有する既存runtime directoryのmodeを0700へ直すだけで、symlink・他所有者・SDK導入・socket削除・daemon起動は扱いません。

<a id="mcp"></a>
## MCP stdioサーバー

初期設定は[エージェント連携ガイド](https://r0227n.github.io/marionette_agent/ja/guides/agents/)を参照してください。profileはcommaで合成します。tool名の共通prefixは`marionette_agent_`です。

| Profile | Tool名の末尾 |
| --- | --- |
| `core`（既定） | connect, launch, snapshot, tap, fill, swipe, scroll, screenshot, get_text, get_box, get_count, is_visible, wait, close, session_list, session_show |
| `inspect` | get_value, is_enabled, is_checked, logs, doctor, device_list |
| `actions` | dblclick, focus, hover, check, uncheck, scrollintoview, type, select, press, keydown, keyup, keyboard_press, keyboard_type, keyboard_inserttext, clipboard_read, clipboard_write, clipboard_copy, clipboard_paste, drag |
| `workflow` | workflow_run, workflow_validate, workflow_schema, batch, confirm, deny |
| `record` | record_start, record_restart, record_stop, record_status |
| `all` | 上記すべて |

`marionette_agent_tools_profiles`は常に利用できます。find/diff/state/skills/install/upgradeはMCPに公開していません。`tools/list`は20件ずつで、返却された`nextCursor`を次の`cursor`へ渡します。省略/nullは先頭、不正値・型はJSON-RPC `-32602`です。無効profileのtoolは呼べません。

各toolの`inputSchema`を入力の正本として使用してください。`target`はref/key/identifier/text/typeのいずれか1つです。要求の`session`、`timeoutMs`、`maxOutput`、`contentBoundaries`は起動時指定より優先します。接続・対象解決・policy・ref失効はCLIと同じです。

CLI toolのtextと`structuredContent`には`{exitCode,response}`を返し、responseは通常のCLI包絡です。失敗は`isError:true`でcode/outcomeを保持します。tools_profilesはprofile情報を直接返します。screenshotのinline画像は合計16 MiBまでで、超過・読込失敗は保存pathと省略理由を返します。

起動時の`--restore`と`--confirm-interactive`、workflow/batchのstdin `-`は拒否します。stdoutはMCP専用です。stdin EOFでサーバーが終了してもdaemon/sessionは残るため、明示closeしてください。通信断はUI操作の取消しを保証しません。HTTP transportとcancellationは未対応です。

<a id="skills"></a>
## 同梱Skillの配布と形式

`skills list`は名前順、`get`は指定順でfrontmatter付き全文を返します。`--all`は非表示でない全Skillを名前順に選び、指定名より優先します。`--full`は`references/`と`templates/`直下のtextを追加し、再帰探索・実行はしません。空nameや独立した`---`行で囲まれていないfrontmatterは除外し、LF/CRLFを受理します。

`core`と`simulator-verify`が通常のbundleです。導入stubの`marionette-agent`はhiddenで、名前を指定すればget/pathできます。`MARIONETTE_AGENT_SKILLS_DIR`が既存directoryならそこだけを検索し、未設定・不存在なら同梱先を使います。

SkillsのJSONは通常のCLI包絡と異なります。

```json
{"success":true,"data":[{"name":"core","content":"..."}]}
```

listのdataはname/description、getはname/contentの配列です。fullは補助ファイルがあれば`files:[{path,content}]`を追加します。pathは`{paths:[...]}`、名前付きは`{name,path}`、helpは`{help}`です。成功は終了0、未知名・引数・config不正・探索失敗・timeoutは終了1で`{success:false,error:"..."}`です。text失敗はstderrだけに出し、session/schemaVersion/outcomeは返しません。restoreやpolicyによるアプリ処理は行いません。

install/upgradeはローカルsourceをAOTコンパイルし、隣接する専用`.marionette-agent-*`bundleを配置します。新規配置失敗では新bundleを回収し、既存バイナリを維持します。upgrade後の旧bundleは旧プロセス用に残るため、不要になったことを確認して整理してください。`skills path`で使用中の場所を調べられます。

<a id="capture"></a>
## 画像保存と注釈の境界条件

基本操作は[画像・動画ガイド](https://r0227n.github.io/marionette_agent/ja/guides/capture/)を参照してください。明示pathがあれば`--screenshot-dir`を検査しません。directory指定時の自動名は`screen-<32桁hex>.png`または`.jpg`、両方省略時はprivate一時directoryの`screen.png`または`screen.jpg`です。複数画像は拡張子前に`-1`、`-2`を付けます。

拡張子はPNGなら`.png`、JPEGなら`.jpg/.jpeg`で、大文字小文字を区別せず綴りを保持します。拡張子なしなら形式に応じて補います。形式の自動推定はしません。JPEG品質の既定は90、0はencoderの1と同じで、100もlosslessではありません。PNGは元のbytes・寸法・透過を保ちます。JPEGは同じ寸法で透過を白へ合成します。

親directoryは事前作成が必要です。指定directory自身のsymlinkは拒否し、祖先のsymlinkは利用できます。全画像を検証・変換し、全保存先を排他的に予約してから書き込みます。既存file/directory/symlinkは上書きしません。期限には取得・変換・保存を含み、途中失敗では作成した画像の削除を試みます。OSの削除拒否や進行中I/Oの即時取消しは保証できず、失敗時は成功pathsを返しません。

注釈はmapped providerと有効snapshotが必要です。返却metadataは`annotated`、`generation`、`annotationCount`、`skippedAnnotations`です。省略理由は`missing_or_invalid_bounds`、`bounds_outside_view`、`label_space_exhausted`。capture前後の対象変更はSTALE_REF、複数画像・回転・不明な画像/view対応・PNG寸法不一致はUNSUPPORTED_CAPABILITYです。JPEGはPNGへ注釈後に変換します。refは更新しません。領域cropと注釈は併用できません。

<a id="recording"></a>
## 録画の寿命と復旧

1 sessionにつき1録画、同じdaemon内では1端末/displayにつき1録画です。録画だけのsessionは接続状態disconnectedでも、`record status`で確認できます。recordは操作用refを変更しません。

stateは`starting/recording/stopping/stopped/failed`、未録画は`idle`です。stopは重複しても同じ最終結果を返します。`elapsedMs`は確定処理を含む壁時計時間で、再生時間ではありません。失敗時の`failure`と`recoveryPath`を確認してください。

開始待ちは最大30秒です。開始timeout後も所有processと予約を回収し、終了確認まで次の同一端末録画を拒否します。停止timeoutでも確定処理は続くのでstatusで確認します。restartは旧動画の確定と新規開始が原子的ではありません。引数・既存pathは停止前に検査しますが、新規開始に失敗しても旧録画を再開しません。

Flutter方式はPNG取得後にstart成功となり、停止時に最大30秒でH.264 MP4へ変換します。ffmpegのPNG decoder、libx264 encoder、concat demuxer、setts bitstream filterが必要です。取得完了後にfps相当の間隔を待つVFR方式です。寸法変更・取得用接続断・変換失敗を成功に置換しません。高速アニメーション、host sleep、hot restart中の継続は保証しません。

端末方式ではiOS/AndroidはMP4、macOS/WebはMOVです。Android screenrecordは180秒で停止・回収し、自動分割しません。iOSは最初のframe、Androidはheader、macOSはprocessの1秒生存で開始を確認します。OS方式の`--fps`は1〜60で保存動画のfpsを指定し、取得cadenceではありません。事前にffmpegを検査し、停止後に変換します。

通常終了とSIGINT/SIGTERMでは確定を最大60秒待ち、追加後処理は最大5秒です。未確定動画は保存先の親にある`.marionette-record-*`へ復旧用として残す場合があります。SIGKILL・host停止後の自動復元、切断Android端末の停止、Android回転中の録画は保証しません。

<a id="web-recording"></a>
## Webのdisplay指定

macOS上の可視Chromeを専用profileとloopback remote-debugging portで起動し、`/json/list`から対象pageを選びます。deviceはdisplay番号だけではなく、以下の形式です。ACTUALIDを選んだ`webSocketDebuggerUrl`のIDへ置き換えます。

```sh
marionette-agent --session web-demo record start ./web.mov --platform web \
  --device 'display:1@ws://127.0.0.1:9222/devtools/page/ACTUALID' --json
```

displayは1〜999です。画面収録許可が必要で、指定display全体に映る他アプリやOSダイアログも含みます。Chromeの配置確認・移動追従はしません。localhost、remote host、認証情報、query、fragmentはdeviceに使えません。headless Chromeはこの方式では非対応です。

同一displayのWeb/macOS録画は排他です。対象tabの終了・crash・debug接続断はCONNECTION_LOSTとなり、statusはfailed、stopはエラーを返します。復旧pathを確認してください。方式と起動例の詳細は[Web録画設計](../web-recording.md)を参照してください。
