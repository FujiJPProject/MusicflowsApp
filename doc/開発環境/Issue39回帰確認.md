# Issue #39 回帰確認（今回固有）

実行結果欄は検証担当者が記録する。未実施を合格扱いにしない。

| 順番 | 確認 | 合格条件 | 結果 |
|---|---|---|---|
| 1 | git diff --check main...HEAD | 空白・競合問題なし | 未実施 |
| 2 | scripts/local/*.sh を1ファイルずつ bash -n | 13ファイル構文正常 | 13/13 合格（下記記録） |
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

診断API無効化検証では Terraform tfvars の test_apis_enabled=false を設定、Plan/Apply、Runtime Config再配備、Backendの設定反映を行う。本番のHTTPS要件は緩めない。旧Shellの削除判定および削除済み資産の回帰確認は削除保留一覧に従う。

## AI側の検証記録

対象ソース: `843d556e11ec1dd9abf9ec5ddbc6d9ad44e6fd48`。2026-11-27にGitHubコネクタから取得した内容を使用。検証用のShell13本、Python2本はGitHubのBlob SHAと `git hash-object` が一致していることを確認してから検証した。

| 確認内容 | 結果 |
|---|---|
| Bash構文チェック | 13/13 合格 |
| Runtime Config単体テスト `python3 -m unittest discover -s scripts/tests -v` | 11/11 合格 |
| Compose統合・マウント・公開ポート・Terraform Output・Worker/診断フラグのコード照合 | 関連する定義・利用箇所を静的レビュー。実行時の挙動は未確認 |
| 削除済み資産・設定・残存Shell・ドキュメントの照合 | 削除履歴と保留対象を分離。全リポジトリの git grep による再確認は実機で実施 |
| 全差分の `git diff --check` | GitHubへの直接接続がDNSエラーのため完全なGit作業ツリーを取得できず、未実施 |
| Docker、Terraform、実機のビルド・回帰検証 | この環境にDocker/Terraformがないため未実施 |

構文チェックを行ったBlob SHA:

| Shell | SHA |
|---|---|
| build.sh | 6eb987dd5d609f516ad1b0afa6ff2840d381c4c0 |
| check.sh | 8b37b77a8903fa4814ff4099d88653fe45753bc0 |
| common.sh | d204192fe76ee2ee5172ab4b364001343c060d65 |
| deploy-frontend.sh | 83c27ff10837fe41b609574b8ec8bf03382862c8 |
| export-frontend-config.sh | 7e23a8170a5cc2bddff42462a2a858ff4cf3327f |
| put-db-secret.sh | 5b654915f09dec879b049dd206dee7d0dd728cb1 |
| seed-cognito-user.sh | f37e5642af5544a9f4133fb546ca60c024549dce |
| setup.sh | a2f0e221a71ac7973e3ae0fb88b44f9df0fd504f |
| start.sh | c5cda86a57c808ccc417fada7bb432619ac61c57 |
| stop.sh | 7efdd3ab386251dd78893f8c11259190a3bfd37a |
| terraform.sh | e5ca55784f6854a21b4e60f9c129898941539527 |
| upload-lambda-artifacts.sh | e20fccdbe6478381f5599da9684f7e421881d9bf |
| worker-mode.sh | deb13db49ecffad33b12fe8c5da3c04abac3516d |

構文合格は起動成功や排他制御の実証を意味しない。

## 人間側の検証開始前に実行する静的チェック

各コマンドの終了コードを確認する。エラーが出たら後続工程へ進まない。親ターミナルで `set -e` を有効化しない。

```bash
set +eu
git branch --show-current
git status --short
git diff --check main...HEAD
git diff --stat main...HEAD
git grep -n -I -E 'hero\.png|react\.svg|vite\.svg|icons\.svg|SECURITY_ENABLED|AUTHORIZER_NAME' -- frontend backend floci scripts terraform docker-compose.yml
```

削除対象の参照なし（git grepは終了コード1）を期待する。終了コード2以上は検索エラー。診断・削除記録の文書上の参照は区別する。

```bash
(
  set -e
  for f in scripts/local/*.sh; do bash -n "$f"; done
  for f in floci/init/ready.d/*.sh scripts/deploy-frontend-local.sh; do sh -n "$f"; done
)
```

Pythonがホストにない場合は、Floci起動後に以下を実行する。

```bash
source scripts/local/common.sh
require_password
dc exec -T -e PYTHONDONTWRITEBYTECODE=1 floci python3 -m unittest discover -s /app/scripts/tests -v
```

各検証結果はこの文書へ追記する。Issue #39の完了・旧初期化Shellの削除・マージは、実環境の結果を確認した後に判断する。
