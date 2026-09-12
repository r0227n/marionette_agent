# Semantics selector・値と状態取得の設計案 (Issue #14)

状態: 固定依存のソース調査とSimulator実payload・画面照合済み。これは将来案であり、CLI機能の実装完了を示さない。現在の契約は [SPEC](SPEC.md)、実装境界は [ARCHITECTURE](ARCHITECTURE.md)。[検証記録と再現手順](../packages/marionette_agent/docs/verification/issue-14.md) に実施結果と人間の確認手順を記録する。

## 調査対象と根拠

基点は `50ccf97f47ecf03a51ea3c5646c9164325570c0b`。調査日: 2026-09-12。依存は配布済み [marionette_flutter 0.6.0](https://pub.dev/packages/marionette_flutter/versions/0.6.0) と [marionette_mcp 0.6.0](https://pub.dev/packages/marionette_mcp/versions/0.6.0)。隣接repoや上流mainの挙動を固定版へ外挿しない。以下のファイル位置は解決済みpackageのrootからの相対pathであり、行番号はこの版のもの。

| ID | 版・ソース | 根拠 |
| --- | --- | --- |
| F1 | marionette_flutter 0.6.0 `lib/src/services/element_tree_finder.dart:24` | Widget elementを再帰走査し、設定による打切りとhit-test filterを適用。完全なSemantics treeではない |
| F2 | 同 `element_tree_finder.dart:42` | text/key/interactive条件で採用。`debugFillProperties`の非null値を条件付きで`toString()`し、type/key/text/bounds/visibleを追加 |
| F3 | 同 `element_tree_finder.dart:138` | Semanticsの非空label/valueを表示textへ変換。両方なら`label: value`。照合経路とは別 |
| F4 | 同 `lib/src/binding/marionette_configuration.dart:129`、`:160` | text抽出は組込み5型、次にアプリのextractText callback。interactive型とTextで走査を打切る |
| F5 | 同 `marionette_configuration.dart:165` | Text/RichTextの表示文字列、EditableTextのcontroller.text、TextField/TextFormFieldのnullable controller.textをtextとして取得 |
| F6 | 同 `lib/src/services/widget_matcher.dart:13` | wire matcherはfocused、座標、key、text、typeのみ。TextMatcherはF4を使い、F3を使わない |
| F7 | 同 `lib/src/services/widget_finder.dart:29` | matcherで最初のWidget elementを検索。CLIの事前一意性確認と送信はatomicではない |
| F8 | 同 `lib/src/binding/extensions/info_extensions.dart:54` | interactiveElementsはF1のlistをそのまま返す。型付きstate APIを追加しない |
| M1 | marionette_mcp 0.6.0 `lib/src/vm_service/vm_service_connector.dart:279` | getInteractiveElementsはextension呼出し。tap/enterTextはMapのmatcherを渡す。新属性の意味を補完しない |
| A1 | [backend.dart](../packages/marionette_agent/lib/src/backend/backend.dart)、[marionette_backend.dart](../packages/marionette_agent/lib/src/backend/marionette_backend.dart) `decodeElements` | 現行DTOはtype/text/key/identifier/bounds/visible。診断属性の全量を公開しない。照合対応はkey/text/type |
| T1 | Flutter 3.47.2 `packages/flutter/lib/src/semantics/semantics.dart:2690` | SemanticsPropertiesのdiagnosticsはlabel/value/hint/tooltip/role/checked/mixed等を追加する。診断からtyped APIは成立しない |
| T2 | Flutter 3.47.2 `packages/flutter/lib/src/widgets/basic.dart:7979` | Semantics.debugFillPropertiesはpropertiesのdiagnosticsも追加する |
| T3 | Flutter 3.47.2 `packages/flutter/lib/src/material/text_field.dart:974` | nullable enabled、controller、decoration等のdiagnostics。decoration内のhintをplaceholder fieldと見なさない |

F2は `p.runtimeType != DiagnosticsProperty`、name/value非nullで選別する。generic型を含むruntimeTypeの比較やFlutterの診断実装に依存するため、特定の診断keyの存在・欠落は実payloadで確認する。文字列`"false"`はJSON boolではなく、プロパティ名`value`だけでは入力値・チェック状態・Semantics値のどれか確定しない。

## 候補属性の能力表

「取得」はraw bindingと現行CLIを分ける。診断由来の「条件付き」はWidget型・非null設定・SDKの診断実装に依存するという意味であり、共通の型付き取得保証ではない。下の実測表に今回確認できた条件を示す。全ての新属性matcherはF6に存在しない。

| 候補 | 固定0.6.0の取得範囲 / CLI | 照合 | 根拠 | 欠けるprimitive・条件 |
| --- | --- | --- | --- | --- |
| role相当 | runtime widget typeは取得・公開可。Semantics roleは診断文字列の候補。typeからbutton等のroleを断定不可 | typeの完全一致のみ。role不可 | F2, F6, T1, A1 | 正規化role enum、由来、対象Widgetへの対応 |
| label | 明示Semantics labelはdisplay textへ混入。独立label診断は条件付き。CLIの独立labelなし | label不可。Semantics fallback textもTextMatcherでは一致しない | F3, F6, T1 | 独立label field、取得元、同一対象へのlabel matcher |
| hint | Semantics hintの診断文字列は条件付き。F3のtextにhintは含めない。CLI未公開 | 不可 | F3, T1, A1 | 型付きhintと照合能力。hintは操作説明でありplaceholderと別 |
| placeholder | TextFieldのInputDecoration.hintText専用取得なし。decorationのtoStringは構造化値ではない | 不可 | F2, T3 | 独立placeholder、null/空文字、対象入力Widgetの同定 |
| value (入力) | EditableText等のcontroller内容がtextになる場合あり。controller省略TextFieldではnullで、内部値を読める保証なし。CLIにtyped input valueなし | 一部組込み型でtext照合可。value selectorは不可 | F4, F5, A1 | inputValue field、control種別、読み取り範囲、秘匿値のredacted状態 |
| value (Semantics) | 明示値はF3でlabelと結合。独立value診断は条件付き。入力値と同義ではない | 不可 | F3, T1 | semanticValue field、由来、Widgetとの対応。結合textの逆parseは禁止 |
| tooltip | Semantics tooltip等のdiagnosticsは条件付き。全Widget共通の保証なし、CLI未公開 | 不可 | F2, T1, A1 | 型付きtooltip、対象対応、tooltip matcher |
| enabled | TextField等の非null設定の診断は候補。effective enabledや親による抑止を共通取得するAPIなし、CLI未公開 | 不可 | F2, T3, A1 | resolved enabled、applicability、unknownの理由。visible/hittableとの区別 |
| checked | 明示Semantics checked/mixedの診断は候補。一般のCheckbox/Switchのtyped state APIなし、CLI未公開 | 不可 | F2, T1, A1 | checked/unchecked/mixedのenum、applicability、WidgetとSemanticsの対応 |

現行 [response fixture](../packages/marionette_agent/test/fixtures/binding_0_6_0.json) の `inspect` はFilledButtonと2個のSemanticsを含み、`Volume: 70%` と `Read only` はF3と整合する表示例。診断label/value/checked等を含まないため、それらの有無を立証しない。FilledButtonの`text: Tap me`もstock exampleで同じraw応答になる証拠ではない (F4はbuttonで打切り、組込みtext抽出にbuttonを含まない)。これはadapter用の合成fixtureであり、実端末採取fixtureとして扱わない。

## Simulatorで確認した範囲

Flutter 3.47.2 / iOS 26.2の予約iPadで、変更していないexampleと[一時研究fixture](../packages/marionette_agent/docs/verification/issue-14-research-fixture.md)を順に起動した。[実payload抜粋](../packages/marionette_agent/docs/verification/issue-14-payloads.json)は対象element内の全fieldを保持し、rawとCLI DTOを並べて保存している。string diagnosticsをbool/enum/input valueへ昇格させていない。

| 属性 | 実payload・画面の結果 | 判断 |
| --- | --- | --- |
| role相当 | 明示Semanticsに`role: "SemanticsRole.tabPanel"`。CLIは`type: "Semantics"`のみ保持 | roleは診断string。typed role/matcherの保証なし |
| label | `semantics_full.label: "Volume"`。別keyの2要素に同じ`"Shared label"`。CLIには独立labelなし | rawで独立labelを観測できたが、操作matcherなし。重複は残る |
| hint/placeholder | Semanticsのhintは`"Adjust volume"`。入力placeholderはdecoration診断文字列内だけで、独立fieldなし | hintとplaceholderを別属性に保つ。decorationをparseしない |
| input value | 通常exampleをfillすると画面にissue14/7 characters、clear後は空欄/0 characters。3段階ともTextFieldのraw/CLIにtext/valueなし。明示controllerの研究入力では`text: "actual input"`を観測 | controller省略時の内部値取得は保証不可。textをget valueと呼ばない |
| semantic value | 明示Semanticsのraw `value: "70%"` と `text: "Volume: 70%"`。CLIはtextだけ | input valueとは異なる診断。結合textの逆parse禁止 |
| tooltip | Semanticsで`"Volume help"`、IconButtonで`"Help tooltip"`というraw string。CLIにはなし | 診断観測のみ。共通tooltip取得/照合なし |
| enabled | 明示TextField true/falseとFilledButton trueはraw string。nullable TextFieldと明示`Semantics(enabled:false)`にはenabled fieldなし。無効入力も`visible:true` | 欠落をfalseにしない。visible/hittableはenabledでない |
| checked | 明示Semanticsのcheckedは`"true"`/`"false"`、mixedは`"true"`。実画面でmixedのCheckboxはrawにもchecked/value/mixedなし | 診断stringから汎用stateを構成しない。混合状態とunknownを区別 |

現行CLIのread-only `wait`で、`--text 'Shared label'`はAMBIGUOUS_TARGET、`--text 'Volume: 70%'`はUNRESOLVABLE_TARGET、`--identifier semantics_full`はUNSUPPORTED_CAPABILITYを確認した。全て`outcome:not_sent`で、前後画面も同一だった。新しいlabel selectorの動作を検証したものではない。

## 型付きDTO案

以下は新規実装時の型案。既存schemaVersion 1へ無断で追加しない。wire schema、capability version、出力互換性を実装Issueで確定する。

```text
Observation<T> = Known<T>(value, provenance)
               | Unknown(reason)
               | NotApplicable
               | Unsupported(capability)
               | Redacted
Provenance = {source: widgetProperty | semanticsProperty | semanticsNode,
              sourceId, backendVersion, observationEpoch}
CheckedState = checked | unchecked | mixed
ElementObservation = {
  identity: {connectionEpoch, treeEpoch, widgetId?, semanticsNodeId?},
  display: {text: String?, textSource: builtIn | custom | semantics | unknown},
  attributes: {
    role: Observation<Role>, label: Observation<String?>,
    hint: Observation<String?>, placeholder: Observation<String?>,
    tooltip: Observation<String?>, inputValue: Observation<String?>,
    semanticValue: Observation<String?>, enabled: Observation<bool>,
    checked: Observation<CheckedState>
  },
  matching: Map<SelectorKind, MatchAttribute>,
  bounds, visible
}
MatchAttribute = {value: String, provenance, backendTargetId?, matchable: bool}
```

`Known(null)`は「対応APIが読取りに成功し、値なしと明示した」場合だけ。field欠落や由来不明は`Unknown`、capability自体がなければ`Unsupported`。空文字は既知値でありnullと異なる。enabledのnullをfalseへ変換しない。checkedのmixedはbool nullから推定せず、上流が三状態の意味を明示した場合に限る。Widgetがチェック対象でないと明示された場合はNotApplicable、欠落だけならUnknown。

displayは人間・agent向け観測値、matchingは同じbackendが同じ対象に照合できる属性。raw diagnosticsや表示textからinputValue/enabled/checkedを生成しない。F5のtextがcontroller由来でも現行DTOに由来証明がないため、現行`text`をget valueの代用にしない。将来の限定対応は明示controllerの対象型と取得元を保証するbackend field/primitiveを必要とする。obscured inputはRedactedを区別し、取得データを診断へ流さない。

## 共通selectorとread-only操作案

共通SelectorKindに`role`、`label`、`hint`、`placeholder`、`tooltip`を追加する案。`value`は変動する状態の読取りを先行させ、今回のselector追加候補に含めない。文字列は完全一致、暗黙のtrim/case-fold/部分一致をしない。labelとhintとplaceholderは別属性である。独立find構文、first/last/nth actionは導入しない。

parser、workflow schema、共通対象解決、snapshotの候補集計、wait、backend adapterの同じSelectorKindを拡張する。tap/fill/swipe/scrollのtarget、waitのselector、workflow stepは同一解決経路を利用する。`wait`は引き続きref/座標を受けない。コマンドごとのlabel解釈や座標への自動fallbackを作らない。selectorの観測対応と操作別送信対応をcapabilityで区別し、片方だけの対応を操作可能と見なさない。

将来のread-only操作は`get value <target>`、`is enabled <target>`、`is checked <target>`相当を想定する (構文は未実装)。既存targetと同じ一意性・ref再検証を使い、同一session queueでreadを1回実行する。成功dataは対象identity、属性名、Observationを返す。checkedはboolへ丸めずmixedを保持する。Unknown/NotApplicable/Redactedは成功した観測の明示状態で、true/falseの成功判定へ変換しない。読取りが未対応ならUNSUPPORTED_CAPABILITY、対象0件ならTARGET_NOT_FOUND、複数ならAMBIGUOUS_TARGET。非対応型を推測でNotApplicableにしない。

将来の有効な構文で要求したcapabilityがなければ `UNSUPPORTED_CAPABILITY`、exit 6、`outcome:not_sent`。既知の非対応はUI送信・ref失効より前に検出する。workflowは既知の非対応を全stepの事前検証で拒否し、開始後に能力が失われた場合は現行の完了step/失敗step契約で停止する。自動再送しない。現行0.6.0でこのコードを返す既存例は`--identifier`であり、未導入の`--label`や`get value`を現在のCLIが受理するという意味ではない。

capabilityを持つbackendで一部要素だけ属性不明なら、snapshotにUnknownを残す。matchingの由来が不明な候補が同じ値を持つ場合も衝突へ数え、2件以上ならAMBIGUOUS_TARGET、唯一でも送信根拠がなければUNRESOLVABLE_TARGET。wait existsも同様、goneは0件だけ成功。不完全な観測範囲で全Semantics treeの不存在を保証しない。

新selectorのcapabilityには候補の観測範囲も必要である。対象scope内の属性欠落が一致候補を隠す可能性がある場合は、一意性やgoneを証明できないためUNRESOLVABLE_TARGETとする。backendがscope内の候補を完全に列挙するか、件数を伴うatomic resolveを提供するまで、新selectorを既存のhit-test済みlistだけで有効化しない。

## 階層・重複・ref

F1はflatなWidget観測で、Semantics node ID、親子関係、merge/exclude境界、読み上げ順、Widgetとの対応を返さない。1つのWidgetが1つのSemantics nodeになるとは限らず、wrapperとchildをlabel/boundsの一致だけで同じ対象へ統合しない。重複labelの別Widgetは2件のまま扱う。上流にconnection/tree epochと安定target ID、Semantics nodeから操作対象への明示対応を求める。対応未確認のSemanticsはdisplay-onlyとして保存する。

将来のrefは既存のconnection/snapshot世代に加え、照合根拠と対象identityを保存する。実行前に再観測し、一致0件・identity/保存属性変化はSTALE_REF、複数一致はAMBIGUOUS_TARGET。backendがinstance置換を区別できるIDを返さない限り、同一属性を持つ別instanceへの置換は検出できない制約を明示する。値・状態はread時の最新値を返し、単なる状態変化だけではref失効にしない。ただし保存selectorの根拠が変化した場合はstale。既存refのtext比較は維持するため、現在の入力text変化ではstaleになり得る。

readは新refを発行せず、成功時に既存refを失効させない。timeout/切断時の接続世代破棄、mutation送信直前の全ref失効は現行契約を継承する。観測と操作の間の競合はCLIだけでは閉じられず、atomicなresolve-and-act/read primitiveが必要。

## 必要fixtureと期待結果

以下は後続実装で必要なfixture仕様であり、追加済みテストを意味しない。

| fixture | 観測/要求 | 期待結果 |
| --- | --- | --- |
| 同じlabelのボタン2個、異なるkey | labelでtap/read/wait exists | AMBIGUOUS_TARGET、UI未送信。keyでは一意に解決 |
| Semantics wrapper + labelの同じchild | ID対応なし | 勝手にdeduplicateしない。複数候補はambiguous |
| nullable enabled、無効、親による抑止 | fieldなし/null/falseを別々に返す | 欠落はUnknown、明示falseだけKnown(false)。visibleをenabledへ流用しない |
| checked false/true/mixed、チェック非対象 | 型付き応答をそれぞれ返す | unchecked/checked/mixed/NotApplicableを区別。欠落はUnknown |
| 由来不明textだけのcustom Widget | textで操作/wait | 唯一ならUNRESOLVABLE_TARGET、既知型と同値ならAMBIGUOUS_TARGET |
| input labelとvalueが異なる、空入力、controller省略 | label=Email、inputValueなし | display textから値を作らない。現行get valueは未実装、将来非対応backendはUNSUPPORTED_CAPABILITY |
| 明示controllerの入力とobscured入力 | 空文字/既知値/Redacted | 空文字とnullを区別、秘匿理由を保持、診断に内容を出さない |
| Semantics label/valueにcolon、空文字を含む | F3の結合text | splitで元のlabel/valueを復元しない |
| hintとplaceholderとtooltipが異なる | 各selectorで照合 | 対応する属性のみ照合。属性間fallbackなし |
| binding 0.6.0またはcapability欠落 | 将来label/read state要求 | UNSUPPORTED_CAPABILITY、not_sent、ref維持。workflow事前検証で拒否 |
| 同じlabelの対象置換、epoch変化 | 保存refでread/action | 安定IDが変化すればSTALE_REF。ID未提供では検出制約を記録 |

## 実装へ進む条件と未解決依存

| 区分 | 次に進める内容 / 依存 |
| --- | --- |
| 現在実装済み | key/text/type照合、identifierの非対応判定、display text、既存のref・wait・workflow。追加機能の完了扱いにはしない |
| CLI側で設計可能 | Observation DTO、capability table、共通selector経路、未知状態/error fixtures、versioned schema。実装は別Issue |
| 固定版で調査可能 | raw診断と正規化snapshotの差、F3/F5の限定取得、exampleのcontroller省略時の観測。実payload確認後も共通typed能力と混同しない |
| backend/上流待ち | 型付きlabel/hint/placeholder/tooltip/inputValue/semanticValue/enabled/checked、由来と適用範囲、selector matcher、Semanticsと操作対象IDの対応、atomic読取り/操作 |
| 後続scrollintoview | 0.6.0にはM1の`scrollToElement`と`scroll_simulator.dart`の探索/drag primitiveが既にある。ただしCLI adapterは未公開で、label対応や共通一意性・offscreen観測を保証しない。別途統合/受入検証が必要 |
| 後続a11y audit | 完全なSemantics tree、flags/actions/階層・merge情報が必要。F1のhit-test済みflat listではaudit成立を主張できない |

このIssueでは設計・調査記録のみを提供し、新CLI、上流repoの変更、上流Issue投稿は行わない。Simulator実payload・画像の確認結果は記録済みであり、追加機能の実装と上記の上流依存解消は後続作業として残る。人間の確認はDraft PRで未実施として引き渡す。
