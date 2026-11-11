# Musicflows Frontend 開発・配信手順（Issue #37）

> このファイルにフロントエンド関連手順を集約する。変更対象は`MusicflowsApp`のみ。
> `MusicflowInfra`とTerraform Module / Stateを共有しない。Floci検証コードを実AWSへそのまま適用しない。

## 1. 配信構成と環境

| 画面を開く場所 | 配信元 | 設定 | API |
| --- | --- | --- | --- |
| 通常開発: `http://localhost:5173` | Vite | `frontend/public/config/local-config.json` | Floci / Spring Boot |
| Terraform独立テスト: `http://localhost:5174` | Vite | `.docker-cache/terraform-test/frontend-config/local-config.json`を公開ディレクトリへマウント | Floci |
| Terraform独立テスト: `http://<distribution-id>.cloudfront.localhost.floci.io:4567/` | Floci CloudFront → 非公開S3 | 配信後の`/config/local-config.json` | Floci |
| 実AWSの開発・本番 | AWS CloudFront → 非公開S3 | AWS用`/config/local-config.json` | AWS API Gateway |

Reactソースは同一であり、`npm run build`の生成物を配信先ごとのRuntime Configで動かす。Viteの開発サーバーは残す。`frontend/vite.config.ts`では`base="/"`と`dist/`を指定する。

Flociで使うファイルは`deploymentStage=local`、AWSでは`dev`または`production`とし、AWS用設定からlocalhost、直接Spring Boot URL、ローカルCognito Endpointを排除する。Configが不正な場合、Reactは設定エラーを表示し、localhostへフォールバックしない。ビルド出力は`frontend/dist/`で、Git管理対象外。

## 2. 変更箇所と責務

- `terraform/local/provider.tf`: CloudFront操作もFlociへ固定する。
- `terraform/local/main.tf`, `variables.tf`, `terraform.tfvars.example`: `enable_frontend_delivery=false`を既定とし、Issue #35/#36の単体テストへの影響を防ぐ。
- `terraform/modules/frontend-delivery/{main,variables,outputs}.tf`: **Floci専用**の非公開S3、Block Public Access、Versioning、OAC、S3のSourceArn制限、CloudFront、Cache Policy、SPAフォールバック。
- `terraform/modules/runtime-infrastructure/{lambda,variables}.tf`: Lambdaへ複数CORS許可Originを注入。
- `backend/src/main/java/com/jws/musicflows/config/cors/WebCorsConfig.java`, `backend/src/main/resources/application.yaml`, `backend/src/main/resources/application-lambda.yml`: 明示的な複数Originを許可、空値・ワイルドカードは拒否。
- `docker-compose.terraform-test.yml`: フロントのビルド出力をFlociへ読み取り専用マウント。S3認可検証は明示的オプトイン。
- `scripts/check-frontend-config.py`: デプロイ前にRuntime Configのstage、必須値、URLを検査。
- `scripts/deploy-frontend-local.sh`: Floci専用。ジョブ用バケットへアップロードしない、HTMLを最後に配信する。

`terraform/modules/job-infrastructure/s3.tf`や`floci/init/ready.d/09-export-frontend-config.sh`の既存ジョブ・設定生成経路は変更しない。Git管理外のRuntime Configには秘密情報を保存しない。

## 3. 独立テスト用Flociの前提

この手順は[Issue #35](https://github.com/FujiJPProject/MusicflowsDocument/issues/35)と[Issue #36](https://github.com/FujiJPProject/MusicflowsDocument/issues/36)で作成した**独立**テスト環境を引き継ぐ。特記なきコマンドは`MusicflowsApp/`直下で実行。

```bash
export TEST_PROJECT=music-app-terraform-test
export TEST_COMPOSE=docker-compose.terraform-test.yml
export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"
docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" ps
```

**期待値:** 既存のFloci・PostgreSQLと関連するStateが存在し、Flociホスト公開ポートが`127.0.0.1:4567`。初回であれば先にIssue #36の手順に従ってCognito・Lambda・API Gateway・SSMとRuntime Configを準備する。別のTerraform Stateを使って既存リソースに重複Applyしないこと。

**禁止:** 既存State/Volumeの削除、`docker compose down -v`、既存環境への`terraform destroy`、`MusicflowInfra`への適用。

### 3.1 ローカルCORSとS3認可の条件

`FRONTEND_ORIGIN`は従来の単一Originの後方互換用。`FRONTEND_ALLOWED_ORIGINS`はカンマ区切りで複数を明示する。**`*`は使わない。**

S3のポリシーが実際に効くか検証するには、Flociを**起動する前**に環境変数`FLOCI_SERVICES_S3_ENFORCE_AUTH=true`が必要。既存Issue #36のアクセスに影響する可能性があるので、先に独立Volume・Stateをバックアップし、実行中ジョブがない状態でのみFlociを再作成する。環境変数だけexportしても起動済みコンテナには反映されない。Floci上のS3認可が既存Lambda処理に影響する場合はその場で停止し、無効のまま「非公開検証合格」とは判断しない。

```bash
export FLOCI_SERVICES_S3_ENFORCE_AUTH=true
# 次の操作は独立テスト環境を安全に再作成できると確認した人だけが実行
docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" up -d --no-deps --force-recreate floci
docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" exec -T floci printenv FLOCI_SERVICES_S3_ENFORCE_AUTH
```

**期待値:** `true`。既存S3/SQS/Cognito/Lambda/SSMが維持される。S3認可を有効にした後は、Issue #36でのS3アクセス回帰も実施する。

## 4. Terraformを検証コピーへ反映

Issue #36の既存`terraform.tfvars`やStateを削除・上書きしない。

```bash
mkdir -p .docker-cache/terraform-test/terraform/modules/frontend-delivery
cp terraform/local/*.tf .docker-cache/terraform-test/terraform/local/
cp terraform/modules/frontend-delivery/*.tf \
  .docker-cache/terraform-test/terraform/modules/frontend-delivery/
```

既存の`.docker-cache/terraform-test/terraform/local/terraform.tfvars`に次を追加する。

```hcl
enable_frontend_delivery = true
frontend_bucket_name     = "music-app-local-frontend"
floci_viewer_port        = 4567
```

既存`enable_runtime_infrastructure=true`、Lambda ZIPハッシュ等は維持すること。

```bash
tf_test() {
  docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" --profile tools \
    run --rm --no-deps terraform -chdir=terraform/local "$@"
}
tf_test init
tf_test fmt -check
tf_test validate
tf_test plan -out=frontend.tfplan
```

**期待値:** Planに新規Frontend用S3/CloudFront/OAC/Cache Policy/ポリシーが表示される。既存のS3・SQS・DLQ・Cognito・WorkerにReplace/Destroyがない。API Lambdaの複数Origin設定更新は想定されるが、必ず差分を確認する。Validate/API互換性にエラーがあればApplyしない。

```bash
# 人間がPlan内容を確認した後にのみ実行
tf_test apply frontend.tfplan
tf_test output frontend_bucket_name
tf_test output frontend_distribution_id
tf_test plan -detailed-exitcode
echo "plan exit=$?"
```

**期待値:** Outputは`music-app-local-frontend`と空でないDistribution ID、再Planは差分なしで終了コード0。終了コード1はエラー、2は差分あり。

### 4.1 AWS CLI関数

```bash
aws_test() {
  docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" exec -T floci \
    aws --endpoint-url http://localhost:4566 --region ap-northeast-1 "$@"
}
DIST_ID="$(tf_test output -raw frontend_distribution_id)"
DIST_HOST="$(printf '%s' "$DIST_ID" | tr '[:upper:]' '[:lower:]').cloudfront.localhost.floci.io"
aws_test s3api head-bucket --bucket music-app-local-frontend
aws_test cloudfront get-distribution --id "$DIST_ID"
```

**期待値:** S3/Distributionが存在する。ProviderやFlociの未対応APIが発覚した場合は、代替設定の採否をレビューし、未検証項目を合格としない。

## 5. ViteビルドとRuntime Config

まずIssue #36と同様に、SSMから設定をエクスポートする。

```bash
docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" exec -T \
  -e EXPORT_FRONTEND_CONFIG_FORCE=1 floci \
  sh /app/manual-init/09-export-frontend-config.sh

docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" \
  run --rm --no-deps frontend \
  sh -lc 'npm ci && npm run build'

find frontend/dist -type f | sort
python3 scripts/check-frontend-config.py \
  .docker-cache/terraform-test/frontend-config/local-config.json --stage local
```

**期待値:** `frontend/dist/index.html`と`frontend/dist/assets/`が生成され、設定検証に合格。

`frontend/public/`配下のファイルはViteビルド時に`dist/`へコピーされる。AWSに配布する際は**必ず**`dist/config/`内の旧ローカル設定を除去し、AWS用Configを配置・検証してからアップロードする。AWSでは`--stage dev`または`--stage production`を使う。

AWS用Runtime Configの例（値は実環境のものに置換）：

```json
{
  "deploymentStage": "dev",
  "apiBaseUrl": "https://API_ID.execute-api.ap-northeast-1.amazonaws.com/dev",
  "cognitoUserPoolId": "ap-northeast-1_EXAMPLE",
  "cognitoClientId": "EXAMPLE_CLIENT_ID",
  "awsRegion": "ap-northeast-1",
  "cognitoDomain": "https://example.auth.ap-northeast-1.amazoncognito.com",
  "workerExecutionMode": "lambda",
  "testPagesEnabled": false
}
```

AWSでは`directApiBaseUrl`・`cognitoEndpointUrl`を含めない。`production`ではテストページを無効化。設定不備時はブラウザでもFail Closedでエラーになり、localhostへ接続しない。AWS向けデプロイ操作は本Issueに含めない。

## 6. S3デプロイとCloudFrontの動作確認

```bash
bash scripts/deploy-frontend-local.sh
```

スクリプトは`frontend/dist/`と生成済み設定を検証し、Flociの**Frontend専用**バケットへ順番にアップロードする。ハッシュ付きJS/CSSは`public,max-age=31536000,immutable`、JSONは`no-store,max-age=0`、`index.html`は`no-cache,max-age=0,must-revalidate`。古いハッシュファイルは削除しない。`--delete`は使用しない。

```bash
curl --noproxy '*' -i -H "Host: $DIST_HOST" http://127.0.0.1:4567/
curl --noproxy '*' -i -H "Host: $DIST_HOST" http://127.0.0.1:4567/jobtest
curl --noproxy '*' -i -H "Host: $DIST_HOST" http://127.0.0.1:4567/auth-test
```

**期待値:** HTTP 200でReactのHTMLが返る。次にブラウザで`http://${DIST_HOST}:4567/`、`/jobtest`、`/auth-test`を表示し、ページ再読込でもReactが起動することを確認する（テスト画面は`testPagesEnabled=true`の環境だけ）。

SPAはFlociの403/404カスタムエラーを`index.html`へフォールバックする方式。存在しないJS/CSSへのリクエストでHTMLを返す可能性があるので、実アセットの応答本文・Content-Typeを必ず確認する。AWSではCloudFront FunctionによるSPAパス限定リライトを別途検討する。

## 7. Vite localhostとCloudFrontを同時に使う

Viteは独立テスト環境では`http://localhost:5174`、通常Composeでは`http://localhost:5173`で残る。S3/OACはVite配信を制限しない。

ブラウザでCloudFront配信URLに到達できることを確認した後、両方のOriginからAPIを呼び出せるようにする。下記のCORS OriginはHTTP/HTTPS、ホスト、ポートを含み**パスを含まない**。

```bash
export FRONTEND_ORIGIN=http://localhost:5174
export CLOUDFRONT_ORIGIN="http://${DIST_HOST}:4567"
export FRONTEND_ALLOWED_ORIGINS="${FRONTEND_ORIGIN},${CLOUDFRONT_ORIGIN}"
export FLOCI_CORS_ALLOWED_ORIGINS="$FRONTEND_ALLOWED_ORIGINS"
printf '%s\n' "$FRONTEND_ALLOWED_ORIGINS"
```

`terraform/local/main.tf`のRuntime Moduleは`enable_frontend_delivery=true`のときLambdaの`FRONTEND_ALLOWED_ORIGINS`を自動設定する。設定のPlanがLambda以外の既存リソースを意図せず変更しないことを確認する。

Floci本体のCORS許可は`FLOCI_CORS_ALLOWED_ORIGINS`をComposeに渡して起動する。**起動後にexportするだけでは有効にならない**。必要ならバックアップと安全確認の後にテストFlociを再作成する。

```bash
# 変更対象は独立テストFlociのみ。実行前にジョブ停止とバックアップを確認。
docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" up -d --no-deps --force-recreate floci
docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" exec -T floci \
  printenv FLOCI_SECURITY_EXTRA_CORS_ALLOWED_ORIGINS
```

**期待値:** ViteとCloudFrontの両Originが登録される。Spring Boot直接接続用backendサービスも`FRONTEND_ALLOWED_ORIGINS`を設定する。API Gateway・Cognito側とSpring Security側のCORS処理を両方テストする。

```bash
# API_BASE_URLにはIssue #36の実際のブラウザ向けAPI URLを設定
curl -i -X OPTIONS "${API_BASE_URL}/api/test-jobs" \
  -H "Origin: ${CLOUDFRONT_ORIGIN}" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: authorization,content-type"
```

**期待値:** CORSが許可される（Access-Control-Allow-OriginがCloudFront Originと一致）。同様に`Origin: http://localhost:5174`でも確認。ブラウザ双方でログイン・API登録・S3ジョブ結果を確認する。CORS成功のみでJWT認可成功と判断しない。

## 8. S3のアクセス制御とキャッシュ

```bash
aws_test s3api get-public-access-block --bucket music-app-local-frontend
aws_test s3api get-bucket-policy --bucket music-app-local-frontend
aws_test s3api head-object --bucket music-app-local-frontend --key index.html \
  --query '[ContentType,CacheControl]' --output json
aws_test s3api head-object --bucket music-app-local-frontend \
  --key config/local-config.json --query '[ContentType,CacheControl]' --output json

# 署名なしでの直接S3取得（S3認可を有効化したFlociでのみ検証可）
curl --noproxy '*' -i -H "Host: localhost" \
  http://127.0.0.1:4567/music-app-local-frontend/index.html

aws_test cloudfront create-invalidation --distribution-id "$DIST_ID" \
  --paths "/" "/index.html" "/config/local-config.json"
```

**期待値:** 4つのPublic Access Blockがtrueで、S3ポリシーに`cloudfront.amazonaws.com`とDistributionの`AWS:SourceArn`条件があり、CloudFront経由は200、匿名のS3直接取得は403。CloudFrontのInvalidation APIが成功。

**制約:** Flociは実際のCloudFrontエッジキャッシュを保持しない。TTL、Age、無効化伝播時間は実AWSでの追加検証が必要。S3認可フラグがfalseのとき、直接S3アクセス拒否の検証は成立しない。

## 9. ロールバック

事前に`index.html`と`config/local-config.json`のS3バージョン・旧JS/CSSを保存する。変更後に問題があれば、新しい配信作業を停止し、旧`index.html`とConfigのVersion IDに基づくS3の`copy-object`で旧版を復元し、CloudFrontで`/index.html`・`/config/local-config.json`をInvalidationする。

Terraformに問題があればStateとFloci Volumeのバックアップを確保してから、差分を確認し、既存リソースのReplace/Destroyを伴わない修正だけ適用する。`prevent_destroy`があるためFrontendバケットの削除を安易に実行できない。既存S3やStateの削除は行わない。

## 10. Route 53・ACM・MusicflowInfraとの境界

Issue #37は**FlociのFrontend配信まで**。Route 53 / ACM / 実AWSのS3・CloudFrontは`MusicflowInfra`で独立したコードとして後続で構築する。GitのModule参照、Terraform Stateの共有は**一切しない**。ブラウザ公開のRuntime ConfigのキーとS3オブジェクトキーを契約として維持する。

AWSでのCloudFront独自ドメイン導入時には、us-east-1のACM証明書、Route 53 Alias、CloudFront `aliases` / `viewer_certificate`、API CORS、Cognito OAuthコールバックURLを整合させる。CloudFront標準ドメインで始める段階はRoute 53/ACMの設定は不要。AWSではViewer HTTPS必須、S3 Block Public AccessとOACを実AWS側でも独立して実装する。

## 11. 配信前の設定検証テスト

```bash
python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
```

**期待値:** すべてのテストが成功。AWS用localhostやHTTP、Configのstage相違、秘密情報混入が拒否される。テストは外部AWS/Flociリソースへ書き込まない。Terraformの`validate`や実際のブラウザ検証とは別に実施する。

## 12. Issue #37 完了条件（人間が確認する）

- [ ] Viteによる開発サーバー配信（localhost:5174）が従来どおり動作。
- [ ] Vite Production Buildが成功し、静的ファイルをFlociの非公開S3へ配置できる。
- [ ] CloudFront経由でSPAの直接URL・ブラウザ再読込が動作する。
- [ ] ViteとCloudFrontを同時に開き、両方からCognitoとAPIが利用可能。
- [ ] S3 Block Public Accessが4項目ともtrue、OACとSourceArn制限がある。
- [ ] 厳格なS3認可のFlociで、匿名直接S3は403、CloudFrontは200。
- [ ] Runtime Configの不足時にデプロイ前検証で失敗し、AWS向けConfigがlocalhostに接続しない。
- [ ] `index.html`・JSON・ハッシュ付きアセットのキャッシュ設定とInvalidation APIを確認。
- [ ] Terraform再Planで差分なし、Issue #35/#36の既存リソースに意図しない変更がない。
- [ ] バージョン復元とキャッシュ無効化によるロールバックを確認。
- [ ] 実AWS、Route 53、ACM、MusicflowInfraのTerraformを変更していない。

**注意:** 現状のAWS用Cognito User Pool ClientにはOAuth認可コード + PKCEに必要な設定が揃っていない。AWS開発環境で認証付きの`/jobtest`を使う場合、Cognito Domain、App ClientのOAuth設定、コールバックURLと`TEST_APIS_ENABLED`の扱いを後続で整備する。実AWSでのCloudFrontキャッシュの挙動も本IssueのFloci試験では検証済みとしない。
