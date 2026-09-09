# Marionette Agent Example

`marionette_flutter: 0.6.0`を固定したdebug専用の検証fixture。Flutter 3.47.2を使用する。起動時にMarionetteBindingとPrintLogCollectorを設定し、操作結果を画面・snapshot・logsで観測できる。入力内容はログへ記録せず文字数だけを画面に表示する。

| key | 検証対象 |
| --- | --- |
| tap_button / tap_result | tapとカウンタ |
| text_input / fill_result | fillで置換・空文字クリア、文字数表示 |
| page_view / page_result | PageView、指のleftで次ページ、rightで前ページ |
| dismissible_item / dismiss_result | leftで削除しItem dismissed表示 |
| operation_scroll_area / scroll_result | スクロールとBottom reached表示 |
| log_button | 手動ログ追加 |

入力欄の外側をtapするとキーボードを閉じられる。初期状態に戻すにはアプリを再起動する。

## 2つの独立したアプリを起動

`flutter devices`で2つのiOS SimulatorのUDIDを確認する。別Simulatorなら同じbundle IDでもプロセス・VM Service・画面状態が独立する。各runnerは別ターミナルで実行する。

```sh
flutter pub get
flutter run -d <SIMULATOR_A_UDID> --debug --no-pub --vmservice-out-file=/tmp/mra-a-uri
flutter run -d <SIMULATOR_B_UDID> --debug --no-pub --vmservice-out-file=/tmp/mra-b-uri
```

URIは認証情報を含むためログ・検証記録へ転記しない。各アプリを別名sessionで接続する。以下はリポジトリルートからの例。

```sh
# シェルのトレース（set -x）は使わない。
CLI=packages/marionette_agent/bin/marionette_agent.dart
dart "$CLI" --session alpha connect "$(cat /tmp/mra-a-uri)"
dart "$CLI" --session beta connect "$(cat /tmp/mra-b-uri)"
dart "$CLI" --session alpha snapshot
dart "$CLI" --session beta snapshot
dart "$CLI" --session alpha tap --key tap_button
dart "$CLI" --session alpha snapshot
dart "$CLI" --session beta snapshot
```

alphaのTap countだけが1、betaは0のままであることを確認する。refは別sessionへ流用できない。alphaのcloseや通信断の後もbetaが操作でき、alphaの再connect後は新snapshotが必要になる。

```sh
dart "$CLI" --session alpha close
dart "$CLI" --session beta close
```

最後にFlutter runnerを`d`でdetachし、URIの一時ファイルを削除する。動作検証はCLIの成功応答に加え、次のsnapshotと画面の変化を確認する。swipe/scrollの方向は指の動きであり、ページ切替・到達を保証しない。

自動widget確認は `flutter test`、CLIのSimulator検証記録は [verification](../packages/marionette_agent/docs/verification/) を参照。

## Workflow検証

Controls/Aboutのタブ（controls_tab/about_tab）とAbout画面のabout_contentをworkflow用に提供する。packages/marionette_agent/examples/workflows/reach-controls.yamlはタブ移動、wait、PageView swipe、snapshotを実行する。JSON版も同じ到達状態を検証する。

アプリを新規起動した状態で、packages/marionette_agentから次を実行する。URIは認証情報を含むので、ファイルのアクセス権を制限する。

```sh
MARIONETTE_TEST_VM_URI_FILE=/tmp/private-vm-uri \
MARIONETTE_TEST_EVIDENCE=/tmp/workflow-results.json \
dart run integration_test/workflow_smoke.dart
```

実装CLIによる20呼出しで、template/binding検証、JSON/YAML実行、最終refの別CLI使用、13 charactersへの変化、不存在targetで2step目停止・Tap count 1を確認する。証跡と3枚のPNGを出力する。

W07でタブ往復後の確認を追加し、現在のworkflow_smokeは24呼出しとなる。Controlsはタブから戻ると再生成されるため、入力表示はNot edited、ページ表示はCurrent page 1へ戻る。入力欄が空であることと併せて4枚目のPNGに記録する。
