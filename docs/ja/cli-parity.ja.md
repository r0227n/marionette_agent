# Flutter向け追加コマンド

agent-browserの操作体系をFlutterへ適用した追加機能です。DOM、CSS、タブ、Cookie、ブラウザー起動設定、MCPの互換実装は含みません。ここに示す構文と出力がmarionette_agentの契約です。

## Flutter側の準備と観測範囲

追加の型付き観測・操作には、同じリポジトリの `packages/marionette_agent_flutter` をアプリへ追加し、debug起動時に `MarionetteBinding.ensureInitialized` の後で `registerAgentExtensions()` を呼びます。exampleは登録済みです。補助パッケージは公開Flutter APIと固定 `marionette_flutter: 0.6.0` を使い、releaseではextensionを登録しません。隣接する参考リポジトリへは依存しません。

providerはmounted Widgetを観測します。完全なSemanticsツリーではなく、遅延構築されていないListViewの行は取得できません。depthは観測対象Widgetの祖先段数で、観測対象外の内部Widgetは数えません。visibleはviewとの交差、Offstage、対象中心のhit-testを調べた値です。中心を操作できるかの観測であり、全画素の可視性を表しません。

- `inputValue`: 単一のEditableTextのcontrollerから取得。パスワード欄は非公開です。
- `enabled`: TextFieldの有効設定、対応するButton／Checkbox／Switch／文字列Dropdownの設定から取得します。readOnlyをdisabledの代用にしません。
- `checked`: Checkbox／Switch／明示Semanticsのbool。mixed、不適用、未観測はunknownです。
- `label`、`placeholder`: 明示Semanticsのlabel、TextFieldのlabelText／hintText。
- `role`: 明示Semanticsのbutton／textField／link／headerフラグだけをbutton／textbox／link／headingへ対応させます。Widget型名から推測しません。

providerなしでは従来のbinding観測を使います。追加属性のreadはunknown、情報を必須とする操作はUNSUPPORTED_CAPABILITYです。double-tapとpressは固定bindingのAPIでも使用できます。アプリの表示textや診断文字列から入力値・状態を復元しません。

## 観測・検索

```sh
marionette-agent snapshot --interactive --compact --depth 4 --json
marionette-agent get value --key advanced_input --json
marionette-agent is enabled --key advanced_input --json
marionette-agent is checked --key advanced_checkbox --json
marionette-agent find role button --name 'Named action' --exact
marionette-agent find label 'Editable' focus
marionette-agent find placeholder 'Type here' type 'hello'
marionette-agent find first --type Checkbox check
marionette-agent find last --type Text
marionette-agent find nth 0 --type TextField
```

`--interactive`はproviderが操作対象と明示した行、`--compact`はref・text・入力値・labelのある行を残します。`--depth`は非負整数。情報がないproviderでinteractive/depthを推測せず終了6にします。全観測の衝突判定とref採番の後で絞り込み、非掲載refは失効します。出力に `options: {interactive, compact, depth}` を追加します。

get value／is enabled／is checkedは `property` と `known`、`value` を返します。空入力はknown=true/value=""、falseの状態はknown=true/value=false、不明はknown=false/value=nullです。読み取りは既存refを保持します。

findはkey／identifier／text／type／role／label／placeholderで検索できます。text／type／label／placeholderは既定で大文字小文字を区別した部分一致、`--exact`で完全一致です。key／identifier／roleは完全一致。`--name`はrole検索だけでlabelを条件に加えます。first／last／nthは既存のselectorを1つ指定し、完全一致の観測順から選びます。nthは0始まりです。

action省略時は `element`、`index`、`matchedCount` を返し、refを発行しません。通常の複数一致はAMBIGUOUS_TARGETです。位置選択後の操作も一意なkey/text/type等へ変換できる必要があり、同属性の要素を添字や座標へ自動フォールバックして操作しません。actionはtap／click／fill、次節の対象付き操作を使用できます。選択後も要素属性を保持し、送信前の再観測で変わった場合はSTALE_REF／not_sentとして操作を拒否します。同じkeyへの置き換わりも属性が異なれば拒否します。

## 入力・操作

```sh
marionette-agent click --key advanced_tab
marionette-agent dblclick --key advanced_double
marionette-agent type --key advanced_input 'hello'
marionette-agent focus --key advanced_input
marionette-agent press Control+A
marionette-agent keydown Shift
marionette-agent keyup Shift
marionette-agent keyboard inserttext 'hello'
marionette-agent keyboard type 'hello'
marionette-agent keyboard press Tab
marionette-agent hover --key advanced_hover
marionette-agent check --key advanced_checkbox
marionette-agent uncheck --key advanced_checkbox
marionette-agent select --key advanced_select two
marionette-agent drag --from-key advanced_drag --to-key advanced_drop
marionette-agent drag @e1 @e2
marionette-agent scrollintoview --key advanced_bottom
```

clickはtapの別名です。対象付き操作ではrefまたは既存selectorを1つ指定します。UI送信直前に共通のref失効処理を行い、自動再送はしません。成功応答の `requiresSnapshot:true` は目的の画面への到達保証ではないため、次のsnapshotや状態取得で確認します。

typeは入力欄をfocusし、現在の選択範囲を置換して文字列を挿入します。選択が無効なら末尾へ追加します。fillは従来どおり全置換です。keyboard type／inserttextは現在focusされたEditableTextに挿入し、Flutterの入力formatter／onChangedを通します。focusはEditableTextか明示FocusNodeを持つFocusが対象です。文字列挿入ではreadOnly・無効入力を拒否します。

pressは下げて上げる1組のキー入力です。enter/tab/escape/backspace/delete/space、arrowup/down/left/right、home/end/pageup/pagedown、a-z、0-9と、control/shift/alt/meta修飾を扱います。Ctrl/Cmd/Command/Option/Esc/Returnも別名として使えます。keydown/upは単一キーまたは修飾キーのみで、重複downと対応するdownのないupを拒否します。close時は補助providerに保持キーの解放を試みます。通信断時の解放は保証できません。

check/uncheckはCheckbox／Switchの変更callbackを必要なときだけ1回呼びます。selectは文字列値のDropdownButtonの有効な項目を選びます。hoverは明示した対象への合成mouseイベント、dragは両対象のref・属性・一意性・可視性を同じ観測で再確認した後の1回のtouchジェスチャーです。これらはFlutter内の操作で、OS全体の入力ではありません。

scrollintoviewは一意に観測できるmounted要素へ `Scrollable.ensureVisible` を1回適用します。未構築の遅延リスト項目を探してジェスチャーを繰り返す機能ではありません。

## 待機・クリップボード

```sh
marionette-agent wait 2000
marionette-agent wait @e1
marionette-agent wait @e1 --state gone
marionette-agent clipboard write 'sample'
marionette-agent clipboard read --json
marionette-agent clipboard copy
marionette-agent clipboard paste
```

時間待機は0以上の整数msで、接続済みsessionのqueueと共通期限を使います。結果は `waitedMs` と `requiresSnapshot:false`。ref待機は直近の有効refが持つselectorを使います。existsは開始時にもref属性を照合し、goneはそのselectorの候補が0件になるまで待ちます。stale／別sessionのrefは拒否します。既存selector待機のstate／poll-intervalも維持します。

clipboardは接続先Flutterアプリのテキストclipboardです。ホストMacのclipboardを代用しません。copyはfocus入力欄の選択文字列、pasteはfocus入力欄への挿入です。パスワード欄のcopyは拒否します。readは `text`（取得できない場合null）と `scope:target_app`、write/copyは `clipboard` とscopeを返してrefを保持し、pasteはUI操作としてrefを失効します。

## 画像と差分

```sh
marionette-agent screenshot --key advanced_input evidence/input.png
marionette-agent screenshot @e1 evidence/input.png
marionette-agent snapshot --json > evidence/baseline.json
marionette-agent diff snapshot --baseline evidence/baseline.json --json
marionette-agent screenshot evidence/baseline.png
marionette-agent diff screenshot --baseline evidence/baseline.png --threshold 0 --output evidence/diff.png --json
```

部分撮影は1つの画像と正しいgeometryを返すmapped screenshot providerが必要です。要素の再観測を撮影前後で照合し、全boundsがview内にある場合だけ切り出します。annotateとの併用は不可。保存形式、deadline、既存ファイル拒否は通常撮影と同じで、結果に `cropped:true` が付きます。

snapshot差分はJSON envelopeまたはsnapshot dataをbaselineとして読み、ref番号・reasonを除いた行を重複件数も含めて比較します。追加／削除を `added`／`removed`、変化の有無を `changed` で返します。順序だけの変更は差分にしません。差分用の現在観測はrefを公開せず、既存refの世代を変更しません。共通max-outputにかかわらず全観測を比較します。

画像差分は同じ寸法のPNGを比較し、RGBA各チャンネルの最大差がthreshold（0〜255）を超えた画素数、総画素数、比率とchangedを返します。output指定時は差分画素を赤く示したPNGを新規保存します。JPEG baseline・異なる寸法・複数画像は非対応です。baselineは32MiB以下の通常ファイルです。新規差分の自動保存・baselineの上書きはしません。

## 設定・session復元・名前空間

```sh
marionette-agent --config config/cli.json --namespace demo snapshot
marionette-agent --session-name demo state save evidence/connection.json
marionette-agent --session demo state load evidence/connection.json
marionette-agent --session demo --restore evidence/connection.json snapshot
```

configは明示した1MiB以下のJSONファイルで、共通オプションの正式名をkey、flagはbool、それ以外は文字列または整数にします。例: `{"session":"demo","timeout":10000,"json":true}`。未知key、config/help/versionの設定、不正な型は拒否します。優先順は明示CLI > session/timeoutの環境変数 > config > 既定値。選ばれなかった設定値の値域は検証しません。相対パスはCLIのcwd基準です。

session-nameはsessionの別名で、重複指定は拒否します。namespaceはsessionと同じ名前規則を使い、runtime directory名へ接尾辞を加えてdaemon・session・refを分離します。socket pathの80byte制限は引き続き適用します。

stateは**接続URIのみ**を保存・復元します。Flutterの任意のアプリ状態、画面、フォーム内容、ref、録画、policyは保存しません。saveは新規ファイルを0600にしてから認証URIを書き、stdoutへURIを返しません。load／restoreは現在ユーザー所有の0600の通常ファイルのみ受理します。接続先アプリは引き続き起動している必要があり、hot restart等でURIが変われば再取得が必要です。restoreは要求前に明示的に再接続し、UI操作を再送しません。

## 連続実行と操作ポリシー

```sh
marionette-agent batch config/steps.json --json
marionette-agent --action-policy config/policy.json connect "$VM_URI"
marionette-agent --confirm-actions tap tap --key advanced_tab
marionette-agent confirm <confirmation-id>
marionette-agent deny <confirmation-id>
marionette-agent --confirm-interactive tap --key advanced_tab
```

batchは1〜100個のargv配列を持つJSONファイル（stdinは `-`）です。例: `[["fill","--key","advanced_input","hello"],["get","value","--key","advanced_input"]]`。全CLI構文を解析してから、1つのsession queue内で順番に実行します。共通オプションはbatch自身に指定します。子コマンドで環境変数やconfigを再解決せず、親が明示CLIで上書きした不正な環境値も再検証しません。接続／切断、録画、ファイル保存、差分、他のbatch/workflowは内包できません。snapshot/get/is/find、入力・操作、wait、logs、clipboardに対応します。

最初の失敗で停止し、応答を受信できた場合は `error.details` のcompleted・failedIndex・results・progressKnownに進捗を返します。通信断で応答を失った場合は進捗を確定できません。成功時はcompleted・results。rollback、再送、途中再開はしません。

policyのJSONは `default:allow|deny` と `allow`／`deny`／`confirm` のコマンド名配列です。例: `{"default":"allow","deny":["drag"],"confirm":["tap"]}`。deny > confirm > allowの順で、allowだけを指定した場合は未掲載操作をdenyにします。対象はUI操作・clipboardの変更・録画開始で、観測やcloseは妨げません。clickとtapは同じ操作として照合します。findのactionとbatch/workflow内の操作も開始前に検査します。

policyはsessionへ保持し、省略時も有効です。明示した新しいpolicyで置換できるため、OSの認可境界ではありません。confirm-actionsはconfirm一覧へ加えます。保留時は `CONFIRMATION_REQUIRED`、detailsにconfirmationIdとcommandを返し、入力値は表示しません。保留はsession内で1件、5分間、同じ接続世代のみ有効で、confirm/deny後は再利用できません。policy変更・切断で破棄します。confirm時も対象の通常の一意性・ref検証を行います。workflow/batchの確認は全体を1回承認します。

confirm-interactiveはTTYがあるときだけstderrへ確認を出し、`y`でconfirm、その他はdenyにします。TTYがなければ保留エラーを返して入力待ちしません。policyの拒否はACTION_DENIED、保留と拒否の終了コードは1、outcomeはnot_sentです。

## 端末・録画・診断・配布

```sh
marionette-agent device list --platform ios --json
marionette-agent device list --platform android --json
marionette-agent record start evidence/first.mp4 --platform ios --device <UDID> --fps 15
marionette-agent record restart evidence/second.mp4 --platform ios --device <UDID> --fps 15
marionette-agent record stop
marionette-agent doctor --quick
marionette-agent doctor --offline
marionette-agent doctor --fix
marionette-agent install --source packages/marionette_agent bin
marionette-agent upgrade --source packages/marionette_agent bin
```

端末一覧は接続不要・起動なしで、利用可能なiOS SimulatorまたはオンラインのAndroid端末の `devices` を返します。

restartは同sessionの現在の録画を確定してから、明示したplatform/deviceと新しいpathで開始します。静的な引数・既存pathは停止前に確認しますが、停止と新規開始は原子的ではなく、新規開始が失敗しても旧録画を再開しません。fpsは1〜60で、OSの取得cadenceではなく保存動画のフレームレートです。指定時は事前にffmpegを確認し、停止後にprivate staging内でlibx264へ変換します。変換中も停止処理は継続し、失敗時はstagingを保持します。fps未指定は従来どおりです。

doctor --quickはhost/runtime/daemonを検査し、依存・端末一覧・VM probeをskippedにします。offlineはVM probeを省略します。fixは既存の自身所有runtime directoryのmodeだけを0700へ修復します。他所有者、symlink、SDK/package導入、socket削除、daemonや端末の起動は扱いません。通常doctorは読み取りのみです。

install／upgradeは指定した**ローカルcheckout**のCLIをDart AOTコンパイルし、既存directory内のmarionette-agentへ配置します。installは既存ファイルを拒否し、upgradeは既存通常ファイルをコンパイル成功後に置換します。ネットワークから最新版を取得したりFlutter SDKを更新したりしません。事前に目的のcheckout・依存・Dart SDKを用意してください。通常sourceは実行中packageから解決し、コンパイル済みCLIからの実行では `--source` を指定します。

同じcheckoutの`skills/`と`skill-data/`も隣接する専用`.marionette-agent-*`bundleへ配置し、バイナリは対応するbundleを参照します。バイナリとbundleを一緒に移動すれば元checkoutがなくても利用できます。upgradeでは新しいbundleを用意し、旧bundleは実行中の旧版用に保持します。新規配置が失敗した場合は新bundleを回収し、既存バイナリを維持します。詳細は[同梱Skillの参照](cli-reference.ja.md#同梱skillの参照)を参照してください。
