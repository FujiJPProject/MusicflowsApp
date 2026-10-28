# Issue #35 — S3・SQS・DLQのTerraform化

対象: [MusicflowsDocument Issue #35](https://github.com/FujiJPProject/MusicflowsDocument/issues/35)

このPRはTerraform定義・Docker実行環境・Shellの切り替え機構のみ提供する。
**`terraform apply` / `import` / Dockerの環境変更はPR作成時点で未実施。**
適用は移行手順と実環境の差分を確認した人間が行う。

## 1. 責務の境界

| 対象 | 管理者 |
| --- | --- |
| S3 `music-app-local-files` | Terraform (`local`) |
| SQS `music-app-local-music-jobs` | Terraform (`local`) |
| DLQ `music-app-local-music-jobs-dlq` | Terraform (`local`) |
| Redrive Policy (`maxReceiveCount=5`) | Terraform (`local`) |
| Lambda ZIPアップロード、Lambda/API Gateway/Cognito/SSM | 既存Shell |
| Event Source Mappingの有効・無効（`WORKER_EXECUTION_MODE`） | 既存Shell |
| IAM Role / Policyの実体 | 別リポジトリ `MusicflowInfra` |
| IAM権限JSONの仕様 | `modules/job-messaging/iam.tf` |

- `terraform/modules/job-messaging`: Floci・AWS共通定義
- `terraform/local`: DockerのFloci（ローカルstate、ダミー資格情報、サービス名Endpoint）
- `terraform/aws`: 実AWSの**開発環境のみ**（S3 Backend、通常のAWS認証、Account IDガード）
- `environments/` は作成しない。AWSの本番環境への適用は範囲外。
- Terraformコンテナは `tools` profile に隔離し通常起動では実行しない。

## 2. Shellからの差分

| 項目 | 旧Shell | Terraform |
| --- | --- | --- |
| S3名 | `music-app-local-files` | 同じ |
| S3 ZIP／結果キー | `_lambda-artifacts/*` / `worker-results/*` | 既存データはTerraformで管理しない |
| SQS名 | `music-app-local-music-jobs` | 同じ |
| VisibilityTimeout | 180秒 | 180秒 |
| Queueの種類 | Standard | Standard |
| MessageRetention | 未明示（通常4日） | 345600秒（import前に実値照合） |
| ReceiveWaitTime | 未明示（通常0秒） | 0秒（import前に実値照合） |
| Encryption・Queue Policy・バケット公開設定 | Shellで未指定 | 新規設定しない |
| DLQ / Redrive | 未実装 | DLQ 14日、maxReceiveCount 5 |
| Lambda Mapping / worker-local切替 | 既存Shell | 変更なし |

**既存属性が想定と異なる場合は、必ずTerraform定義を合わせてからapplyする。**
S3 Public Access BlockやSQS暗号化の追加は、既存動作の維持を優先して本Issueから除外する。

## 3. Terraformコンテナの起動

ホストにTerraformをインストールする必要はない。

```sh
export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"

docker compose --profile tools run --rm --no-deps terraform version
```

TerraformコンテナからFlociは **`http://floci:4566`** で参照する。
ホスト側の `localhost:4566` を使わない。

**通常のComposeは既存Shell管理が既定値**。移行前に `.env.example` を参考に
`.env` を作り、移行後も `S3_SQS_MANAGER=terraform` を永続的に指定する。
`.env` / `terraform.tfstate*` / `*.tfvars` はコミットしない。

## 4. 実行前に行う読取専用の現状確認

`Readme.md` に記載の `awslocal()` を定義しておく。

```sh
BUCKET=music-app-local-files
QUEUE_URL="$(awslocal sqs get-queue-url --queue-name music-app-local-music-jobs --query QueueUrl --output text)"
awslocal s3api get-bucket-location --bucket "$BUCKET"
awslocal s3api list-objects-v2 --bucket "$BUCKET" --query 'Contents[].Key'
awslocal sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names All --output json
awslocal lambda list-event-source-mappings --function-name music-app-local-music-job-worker
```

キューの未処理数／処理中数を確認する。既存のFloci永続化VolumeとTerraform stateを
**操作前にバックアップ**する。既存S3オブジェクト、メッセージ、Cognito設定を保全する。
`docker compose down -v`、`terraform destroy` は移行中禁止。

## 5. まず独立した空のFloci環境で検証

固定コンテナ名・state・永続化Volumeの衝突を避けるため専用Composeを使う。
`.docker-cache` 配下の作業コピーを使用し、**既存環境のstateを使い回さない**。

```sh
mkdir -p .docker-cache/issue35-smoke/terraform
cp -a terraform/. .docker-cache/issue35-smoke/terraform/
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
docker compose -p music-app-issue35 -f docker-compose.issue35-smoke.yml up -d floci
docker compose -p music-app-issue35 -f docker-compose.issue35-smoke.yml \
  --profile tools run --rm --no-deps terraform -chdir=terraform/local init
docker compose -p music-app-issue35 -f docker-compose.issue35-smoke.yml \
  --profile tools run --rm --no-deps terraform -chdir=terraform/local validate
docker compose -p music-app-issue35 -f docker-compose.issue35-smoke.yml \
  --profile tools run --rm --no-deps terraform -chdir=terraform/local plan
```

**以降は人間が出力を確認してから実行**:
`terraform apply`、再`plan -detailed-exitcode`（終了コード0が合格）。
FlociにS3、SQS、DLQ、Redrive Policyができることを確認する。
検証用Flociでは`ready.d`がマウントされていないため、
Terraformだけの構築を検証できる。

SQS単体のRedrive確認は、検証用Flociだけにメッセージを投入し、
可視性タイムアウトの短い受信を繰り返してDLQの本文・件数を確認する。
Lambda経由のRedriveは別途アプリ統合テストで確認する。

## 6. 既存Flociを引き継ぐとき

1. 新規ジョブ受付を停止、worker-localを停止、Lambda Event Source Mappingを無効化して状態収束を確認。
2. FlociのVolume・S3一覧・Queue属性と未処理メッセージを保全する。
3. `.env` を `S3_SQS_MANAGER=terraform`、`FLOCI_INIT_PHASE=bootstrap`、`WORKER_EXECUTION_MODE=lambda` に変更。
4. `docker compose up -d --no-deps --force-recreate floci` でFlociを再起動。01/02と06〜09がスキップされることをログで確認。
5. `terraform/local` を `init` する。
6. **既存S3とSQSをimportする。importしないまま初回applyしない。**

```sh
# bash例。URLはFloci内部から取得した値を使用する。
QUEUE_URL="$(docker compose exec -T floci aws \
  --endpoint-url http://localhost:4566 --region ap-northeast-1 \
  sqs get-queue-url --queue-name music-app-local-music-jobs \
  --query QueueUrl --output text)"

docker compose --profile tools run --rm --no-deps terraform -chdir=terraform/local init
docker compose --profile tools run --rm --no-deps terraform -chdir=terraform/local import \
  module.job_messaging.aws_s3_bucket.files music-app-local-files
docker compose --profile tools run --rm --no-deps terraform -chdir=terraform/local import \
  module.job_messaging.aws_sqs_queue.jobs "$QUEUE_URL"
docker compose --profile tools run --rm --no-deps terraform -chdir=terraform/local plan
```

既存DLQがある場合は先にimportする。**Planに既存S3やSQSのdestroy/replaceがあれば停止。**
差分は原則「DLQ追加・Redrive Policy・現物との差分を解消した属性」に限定。
人間がPlanを確認してからapplyする。

7. `.env` を `S3_SQS_MANAGER=terraform`、`FLOCI_INIT_PHASE=runtime` に変更。
8. `docker compose up -d --no-deps --force-recreate floci` を実行し、06〜09が完了することを確認。
9. frontend/backendを復旧し、Issue 33のLambda/worker-local排他制御とIssue 34の認可判定を再テスト。
10. Floci再起動後も `terraform plan -detailed-exitcode` が **0** になることを確認。

## 7. 状態・障害の切り分け

- stateに存在せずFlociに実体がある場合: backup後に`terraform import`
- stateに存在するがFloci側に実体がない場合: Endpoint/Volumeの接続先を優先調査
- 誤ったアドレスにimportした場合: backup後に`terraform state rm`で紐付けを解除し再import
- `terraform state rm`は実リソースを削除しないが、次のPlanでCreateになり得るため即applyしない
- stateの手動編集・`terraform state push -force`は禁止

## 8. ロールバック

適用前: `.env`を`S3_SQS_MANAGER=shell`、`FLOCI_INIT_PHASE=runtime`へ戻し、Flociだけ再作成。
import/適用後: 受付停止 → 保全 → stateの管理解除が必要か精査 → Shellに切替。
`terraform destroy`は使用しない。
旧Shellに戻しても、新規追加したRedrive Policy/DLQは自動削除されない。
既存メッセージ・DLQの検証が完了するまで属性を戻さない。

## 9. 受入条件

- [ ] Docker内のTerraformで`init`/`validate`/`plan`が成功
- [ ] 空のFlociで`apply`からS3・SQS・DLQを構築可能
- [ ] 再Plan（Floci再起動後を含む）が差分0
- [ ] SQS単体とLambda Event Source Mapping経由のDLQ移送が成功
- [ ] Lambdaモードとworker-localモードの排他制御・S3結果保存が維持
- [ ] APIの認可とS3 403/404の判定が維持（Issue 34）
- [ ] 既存S3オブジェクトとジョブキューのデータが不意に消えない
- [ ] IAM権限JSONとMusicflowInfra側のアタッチ先が確認済み
- [ ] state・ロールバック方針と操作証跡を記録

## 10. AWS開発環境のstate分離

`terraform/aws`は実AWSの開発環境用。今回のPRでは**適用しない**。
MusicflowInfraの `infra/backend/shared.s3.tfbackend` を
`terraform init -backend-config=... `へ渡し、`aws`専用S3キーで保管する。
AWS認証はホストの`~/.aws`を必要時のみTerraformコンテナへread-onlyマウントし、
`AWS_PROFILE`を指定。ローカル実行ではAWS認証情報をマウントしない。
実AWSのAccount IDは`allowed_account_ids`で固定する。
