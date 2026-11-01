# Issue #36：Flociランタイム基盤のTerraform化

このPRではMusicflowsAppのFloci検証環境のみを変更する。MusicflowInfra・実AWS環境は対象外。

## 管理切替

- 従来方式: `S3_SQS_MANAGER=shell` / `RUNTIME_MANAGER=shell`（既定）
- Terraform方式: `S3_SQS_MANAGER=terraform` / `RUNTIME_MANAGER=terraform`
- `enable_runtime_infrastructure=false`が既定。Issue #35のS3/SQS/DLQ単独テストを維持。
- `enable_runtime_infrastructure=true`のとき、API/Worker ZIPのBase64 SHA256が必要。

## 独立テスト手順

1. `export HOST_UID="$(id -u)" HOST_GID="$(id -g)"`。
2. `read -rsp 'Test DB password: ' TEST_DB_PASSWORD; echo; export TEST_DB_PASSWORD`。
3. `mkdir -p .docker-cache/terraform-test/terraform/{local,modules/job-infrastructure,modules/runtime-infrastructure} .docker-cache/terraform-test/{frontend-config,secrets}`。
4. `cp terraform/local/*.tf .docker-cache/terraform-test/terraform/local/`。
5. `cp terraform/modules/job-infrastructure/*.tf .docker-cache/terraform-test/terraform/modules/job-infrastructure/`。
6. `cp terraform/modules/runtime-infrastructure/*.tf .docker-cache/terraform-test/terraform/modules/runtime-infrastructure/`。
7. `cp terraform/local/terraform.tfvars.example .docker-cache/terraform-test/terraform/local/terraform.tfvars`。
8. `terraform.tfvars`で`enable_runtime_infrastructure=true`、`floci_host_url="http://localhost:4567"`、`frontend_origin="http://localhost:5174"`を設定。
9. `cd backend && ./gradlew clean buildLambdaZips --no-daemon && cd ..`。ZIPをBase64 SHA256でハッシュ化し2変数へ設定。
10. `docker compose -p music-app-terraform-test -f docker-compose.terraform-test.yml up -d postgres floci`。
11. `docker compose -p music-app-terraform-test -f docker-compose.terraform-test.yml --profile tools run --rm terraform -chdir=terraform/local init`、`validate`を実行。
12. 空環境の初回のみ `terraform plan -target=module.job_messaging -out=bootstrap.tfplan` → Planを確認してapply。
13. `terraform plan '-target=module.runtime[0].aws_secretsmanager_secret.db' -out=secret.tfplan` → Planを確認してapply。
14. Git管理外の `.docker-cache/terraform-test/secrets/db.json` に `{"host":"postgres","port":"5432","dbname":"music_app","username":"app_user","password":"<secret>"}` を記録し`chmod 600`。AWS CLIで `secretsmanager put-secret-value --secret-id music-app/local/db --secret-string file:///app/secrets/db.json` をFlociコンテナ内から実行。
15. Flociコンテナ内から `s3api put-object` を使用し `/app/lambda/springboot/musicflows-api-lambda.zip` を `s3://music-app-local-files/_lambda-artifacts/musicflows-api-lambda.zip` に、Worker ZIPを対応するキーへ配置。両方の `s3api head-object` 成功を確認。
16. `terraform plan -out=runtime.tfplan` → 確認 → `terraform apply runtime.tfplan`。
17. `docker compose -p music-app-terraform-test -f docker-compose.terraform-test.yml exec -T -e EXPORT_FRONTEND_CONFIG_FORCE=1 floci sh /app/manual-init/09-export-frontend-config.sh`。
18. JSONを確認しfrontendを起動。Cognitoテストユーザーは別途CLIで作成（Terraform Stateにパスワードを置かない）。

Terraformコマンドは次の形式で読み替える。

```bash
docker compose -p music-app-terraform-test -f docker-compose.terraform-test.yml --profile tools run --rm terraform -chdir=terraform/local plan
```

## 検証

- API Gateway → 公開済みLambda Alias `live` → Spring SecurityによるJWT検証が動作。
- `GET /api/health` が200、Tokenなしの `POST /api/test-jobs` が401。
- React `http://localhost:5174/jobtest` からジョブ投入、SQS、Worker Lambda、S3へ結果保存して `processorType=LAMBDA`。
- OPTIONSのCORSで `http://localhost:5174` が許可される。
- 壊れたメッセージは再試行され、DLQへ到達する。
- worker-local切替時はまずMappingをDisabledへ変更し、実行中Lambdaの終了を確認してからworker-localを起動する。
- `terraform plan -detailed-exitcode` がExit 0になる。Floci再起動後にも差分0。

## 既知の留保

- FlociとAWS Provider間のIAM / Lambda Alias / SnapStart / API Gatewayについて、実機検証未実施。
- ZIPのS3アップロードとSecret実値の投入はTerraform外。初回apply前に必須。
- Terraform StateとFloci Volumeを毎回新規にしなければ「空の環境」の再現性テストにならない。
- `floci/floci:latest-compat` は検証成功後にDigestを固定する。
- Docker SocketはホストDockerへの強い権限を持つため、信頼できるローカル開発環境でのみ使用。
- 既存Flociへのimportは後続作業。既存Shellのデフォルト動作は変更しない。
