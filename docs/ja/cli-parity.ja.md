# 追加操作の制約

[English](../cli-parity.md) · [日本語の目次](README.md)

基本構文は[コマンド一覧](https://r0227n.github.io/marionette_agent/ja/reference/commands/)、providerの導入は[アプリ側の準備](https://r0227n.github.io/marionette_agent/ja/getting-started/app-integration/)を参照してください。本書は操作の適用範囲と境界条件を説明します。

<a id="providers"></a>
## providerが観測するもの

`registerAgentExtensions()`はbinding初期化後にdebugで登録します。補助providerはmounted widgetを観測し、完全なSemantics treeやlazy listの未構築要素は返しません。depthは観測対象widgetの祖先数で、Flutter内部elementの全深さではありません。visibilityはviewport交差・Offstage・中心のhit testに基づき、全pixelの可視性を保証しません。

| 属性 | 観測範囲 |
| --- | --- |
| inputValue | 単一EditableTextのcontroller。passwordは返さない |
| enabled | 対応するTextField/Button/Checkbox/Switch/string Dropdown。readOnlyはdisabledとは別 |
| checked | Checkbox/Switchまたは明示Semanticsのbool。mixed/不明はunknown |
| label/placeholder | 明示Semantics、TextFieldのlabelText/hintText |
| role | 明示Semanticsのbutton/textField/link/headerからbutton/textbox/link/headingへ対応。widget名から推測しない |

provider不足時、readはunknownを返す場合があり、必要な情報を得られないactionはUNSUPPORTED_CAPABILITYです。dblclickとpressはbinding APIで実行でき、すべての追加操作が補助providerを要求するわけではありません。表示textからinputValue・enabled・checkedを推測しません。

<a id="snapshot"></a>
## snapshotと型付きread

`--interactive`はproviderが明示した操作候補だけ、`--depth`は非負整数です。必要な観測情報がなければ終了6です。`--compact`はref/text/inputValue/labelを残して詳細を減らします。結果のoptionsは`{interactive,compact,depth}`です。全観測で一意性とref採番を確認してからfilterを適用し、返さなかったrefは無効です。

`get value`と`is enabled/checked`は`property/known/value`を返します。unknownをfalseや空文字へ置き換えず、read成功時は既存refを保持します。

<a id="find"></a>
## findの照合と位置選択

key/identifier/roleは完全一致、text/type/label/placeholderは既定で大文字小文字を区別する部分一致です。`--exact`で完全一致へ変更し、`--name`はroleのlabelだけに適用します。first/last/nthはselectorを1つ取り、観測順で選択します。nthは0始まりです。

actionなしの結果は`element/index/matchedCount`で、新しいrefは発行しません。通常検索の複数一致はAMBIGUOUS_TARGETです。first/last/nthで1件選んでも、実行時には一意で安定したmatcherが必要です。indexや座標へ自動fallbackしません。選択時属性を送信直前まで保持・再検証し、key再利用などの変更はSTALE_REF/not_sentとして操作しません。

<a id="input"></a>
## 入力、キーボード、ジェスチャー

typeはfocus後、選択範囲を置換し、無効なselectionなら末尾に追加します。fillは全体置換です。keyboard type/inserttextはfocus中のEditableTextへ入力し、formatterとonChangedを通します。readOnly/disabledは拒否します。focusはEditableTextか明示FocusNodeのあるFocusを対象にします。

pressはenter/tab/escape/backspace/delete/space、矢印、home/end/pageup/pagedown、英字・数字とcontrol/shift/alt/metaの組合せを受理します。Ctrl/Cmd/Command/Option/Esc/Returnのaliasに対応します。keydown/upは単一keyまたはmodifierで、重複down・対応downのないupを拒否します。close時にreleaseを試みますが、切断時の完了は保証しません。

check/uncheckは必要な場合だけcallbackを1回呼びます。selectはenabledなstring DropdownButtonが対象です。hoverは合成mouse eventです。dragは両対象を同じ観測で検証してから1つのtouch gestureを送信します。いずれもFlutter内の操作で、OS全体のdragやキーボード操作ではありません。

scrollintoviewは観測済みmounted targetへensureVisibleを1回行います。未構築の要素を探してscrollし続ける機能ではありません。

<a id="wait-clipboard"></a>
## 待機とclipboard

時間waitは0以上のmsを取り、session queueと全体期限の中で待ちます。結果は`waitedMs`と`requiresSnapshot:false`です。ref待機は取得時のselectorを保持し、existsでは元の属性も確認、goneでは一致0を待ちます。古いrefを受理しません。IPCの明示nullのstate/pollは既定値扱いせず拒否します。selector待機の詳細は[workflowのwait](workflow-file-spec.ja.md#wait)と共通です。

clipboardはホストCLIではなく接続先アプリのclipboardです。readは`{text,scope:"target_app"}`でtextがnullの場合もあります。copyはfocus中の選択文字列でpasswordを拒否し、pasteはfocus入力へ挿入します。read/write/copyはrefを保持し、pasteはmutationとして失効させます。

<a id="diff"></a>
## cropと差分

領域screenshotはmapped provider、単一画像、view内に完全に収まるboundsが必要です。capture前後に再観測し、倍率を推測せず、結果に`cropped:true`を返します。annotateとの併用は拒否します。

diff snapshotは保存済みの通常包絡またはdataをbaselineとして受理します。ref/reasonと順序は比較せず、重複要素の個数は比較し、`added/removed/changed`を返します。現在の観測ではrefを発行・更新せず、max-outputによる省略前の全体を比較します。

diff screenshotは同寸法の単一PNGだけです。各pixelのRGBA最大channel差がthreshold（0〜255）を超える場合を変更とし、赤く示したPNGを新規pathへ保存します。baselineは32 MiB以下の通常fileで、JPEG・複数画像・baseline上書きは受理しません。

<a id="configuration"></a>
## config、namespace、state

configは明示pathの1 MiB以下のJSON objectで、正規の共通option名を使います。flagはboolean、他はstring/integerです。config/help/versionや未知keyは拒否します。相対pathは呼出元cwd基準です。解決の優先順位は[実行の詳細](cli-reference.ja.md#arguments)に従います。

namespaceはsessionと同じ名前規則でruntime pathへsuffixを追加します。最終socket pathは80 bytes以内です。state保存対象は接続URIだけで、画面・フォーム・ref・録画・policyは含みません。saveは新規0600 fileへ認証URIを書き、stdoutへURIを返しません。load/restoreは現在ユーザー所有の0600の通常fileのみ受理します。アプリが起動中でURIが有効である必要があり、restoreは要求前に接続を復元するだけでUI操作は再送しません。

<a id="batch-policy"></a>
## batchとaction policy

batchは1〜100個のargv配列を持つJSON fileまたはstdin `-`です。全構文を解析してから同じsession queue内で順番に実行します。共通optionは親だけで解決します。snapshot/get/is/find、入力・操作、wait、logs、clipboardを含められます。接続寿命、録画、ファイル保存、差分、batch/workflowの入れ子は拒否します。

成功時は`completed/results`、失敗応答には`error.details`の`completed/failedIndex/results/progressKnown`を返します。通信断では進捗が不明の場合があります。最初の失敗で停止し、rollback・再送・途中再開はしません。

policyは`default:allow|deny`と`allow/deny/confirm`のコマンド名配列です。優先順位はdeny、confirm、allowです。allowだけの指定は未掲載操作をdenyにします。UI操作、clipboard変更、録画開始、launchを対象にし、観測とcloseを妨げません。clickはtapと同じです。find actionとbatch/workflowも開始前に検査し、不正なfind構文はpolicyより先に拒否します。

policyはsessionへ保持され、明示した新policyで置換できます。OSの認可境界ではありません。confirm-actionsはconfirm一覧へ追加します。保留時はCONFIRMATION_REQUIREDと`confirmationId/command`を返し、入力値は表示しません。保留はsession内1件・5分間・同じ接続世代に限り有効で、confirm/deny後の再利用はできません。policy変更・切断で破棄します。confirmでも対象の一意性/refを再検証し、workflow/batchは全体を1回承認します。

confirm-interactiveはTTYのときだけstderrで問い、`y`でconfirm、その他はdenyです。TTYがなければ待機せず保留エラーを返します。ACTION_DENIEDとCONFIRMATION_REQUIREDは終了1、outcome:not_sentです。

録画restart・fps・doctor・install/upgradeの詳細は[CLI実行の詳細](cli-reference.ja.md)へ集約しています。device listは端末を起動せず、利用可能なiOS SimulatorまたはオンラインAndroid端末を返します。
