# Issue #39 回帰確認（今回固有）

実行結果欄は検証担当者が記録する。未実施を合格扱いにしない。

| 順番 | 確認 | 合格条件 | 結果 |
|---|---|---|---|
| 1 | git diff --check main...HEAD | 空白・競合問題なし | 未実施 |
| 2 | bash -n scripts/local/*.sh（1ファイルずつ） | 13ファイル構文正常 | 未実施 |
| 3 | TEST_DB_PASSWORD設定後 docker compose --profile tools --profile worker-local config --quiet | 終了0 | 未実施 |
| 4 | build.sh frontend | Lint/TS/Vite成功 | 未実施 |
| 5 | build.sh backend / lambda | Gradleテスト・ZIP・依存分離成功 | 未実施 |
| 6 | build.sh terraform | Init/Validate成功 | 未実施 |
| 7 | Terraform plan/apply/check | 想定差分のみ、再Plan 0 | 未実施 |
| 8 | setup.sh（空の隔離環境） | 人間承認、完全構築 | 未実施 |
| 9 | 既存環境引継ぎ | State/Volume・DB/S3保持 | 未実施 |
| 10 | check.sh・全画面 | Vite/CloudFront・API応答 | 未実施 |
| 11 | 診断フラグ true/false | 3診断画面有効/無効、API有効/403、health 200 | 未実施 |
| 12 | 未認証/不正JWT/他所有者 | 401/拒否、Local auth/me 500なし | 未実施 |
| 13 | Worker切替 | 排他・COMPLETED/processorType一致 | 未実施 |
| 14 | S3・DLQ・CORS | 結果・再試行・両Origin、未許可Origin拒否 | 未実施 |
| 15 | 停止・再開・失敗再開 | 親ターミナル維持・データ保全 | 未実施 |

診断API無効化検証では Terraform tfvars の test_apis_enabled=false を設定、Plan/Apply、Runtime Config再配備、Backendの設定反映を行う。本番のHTTPS要件は緩めない。旧Shellと未使用候補の削除は削除保留一覧に従う。
