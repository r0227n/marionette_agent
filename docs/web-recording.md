# Web録画方式（Issue #16）

2026-09-13にAPIを確認。利用者の要件はブラウザーUIとOSダイアログも含む証跡である。初回対応はmacOS上の可視Google Chromeとし、録画範囲は利用者が明示したディスプレイ全体、出力は音声なしMOVとする。

| 方式 | 範囲・操作と権限 | 判断 |
| --- | --- | --- |
| getDisplayMedia + MediaRecorder | 利用者の操作を起点に、毎回共有対象を選んで許可する。タブ・window選択ではOSダイアログの範囲が不足し得る。hostへの動画転送・切断後の回収も必要 | 今回は未採用。無人録画できるとは仮定しない |
| CDP Page.startScreencast | Chromeのpage画像をイベントで取得する。専用debug接続が必要。ブラウザーchrome/OSの画面を収録する契約ではない | 要求範囲を満たさないため未採用 |
| macOS screencapture + CDP対象監視 | 利用者が明示したdisplay全体を既存native recorderで取得。実行元アプリにmacOS画面収録許可が必要。CDPは選んだChromeタブの識別と終了監視だけ | 採用。共有録画基盤の権限・保存・終了契約を再利用 |

Chromeは利用者が専用のuser-data-dirとloopback remote-debugging-portで起動し、`/json/list`から選んだpageのendpointを指定する。通常profileをdebug化しない。API選定は「無承認で任意の画面を録れる」という意味ではない。macOS設定で許可を与える操作が必要で、拒否時は失敗する。CLIによる許可の変更や権限ダイアログの迂回は行わない。

displayの配置・選択は利用者が行う。Chromeを移動しても録画先は追従しない。他のwindowで覆われた場合は覆っている内容を収録し、他displayに出たdialogは含まない。ブラウザーは通常操作可能で、Web向け操作コマンドの追加は範囲外。tab終了は失敗とし、別タブを探して継続しない。

- [W3C Screen Capture](https://www.w3.org/TR/screen-capture/): getDisplayMediaの利用者による対象選択・明示許可・transient activation。
- [CDP Page](https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-startScreencast): pageのscreencast frame取得。
- [Chrome remote debuggingの変更](https://developer.chrome.com/blog/remote-debugging-port): Chrome 136以降の専用user-data-dir要件。
- [CDP Target](https://chromedevtools.github.io/devtools-protocol/tot/Target/#method-getTargetInfo)、[Inspector](https://chromedevtools.github.io/devtools-protocol/tot/Inspector/): page identity、detach/crash通知。
- macOS標準`/usr/sbin/screencapture -h`: `-v`の動画と`-D`のdisplay選択。実装では既存macOS backendを使用。

- [Apple CGPreflightScreenCaptureAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29): Web開始前の画面収録許可の読み取り確認。
