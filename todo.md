# Issue #6: close --all

担当: Issue #6 worker / feature/issue-6-close-all

- [x] 既存AGENTS.mdにtodo.md指定・ファイルがないことを確認し、本記録を整備。
- [x] 契約: close --allは全体操作、明示--sessionとの併用はINVALID_ARGUMENT。受付時に全sessionを固定し新規要求を拒否。既存queueを共通deadlineまで待ち、期限超過では接続世代を失効する。送信済み操作はunknown、queue待ちはnot_sent。UI操作は再送しない。
- [x] 結果: session:null、成功data.sessionsにsession別Result。部分失敗はerror.details.sessions、期限超過はexit 5、他の切断失敗はexit 1。全sessionのローカルrefとURI所有権を破棄しdaemon終了。アプリ自体は終了しない。daemon不在は空配列で成功。
- [x] Simulator: 2アプリ、text/JSON各close、未接続・冪等・再connect・画面保持を38 CLI呼出しで確認。4画像を目視し、runner/アプリ停止・両端末Shutdownを確認。
- [x] dart format .、dart analyze（No issues found）、全dart test（--concurrency=1、171件）成功。
- [x] Draft PR用の検証記録・人間の再現手順・4画像を準備。
- [ ] 人間確認（Draft PRで引き渡し）。

詳細な検証記録は packages/marionette_agent/docs/verification/issue-6.md に記録する。
