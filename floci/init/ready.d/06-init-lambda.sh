#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

# ------------------------------------------------------------
# Lambdaデプロイ成果物
# ------------------------------------------------------------

LAMBDA_ARTIFACT_BUCKET="${FILE_BUCKET}"

# API Lambda用ZIPを保存するS3キー。
API_LAMBDA_ARTIFACT_KEY="_lambda-artifacts/musicflows-api-lambda.zip"

# Worker LambdaはAPI Lambdaとは異なるZIPを使用する。
# Spring Cloud Function関連の依存関係をAPI側へ混入させないため、
# 異なるS3キーを使用する。
WORKER_LAMBDA_ARTIFACT_KEY="_lambda-artifacts/musicflows-worker-lambda.zip"

# Spring Boot の bootJar 成果物。
# docker-compose.yml 側で ./backend/build/libs:/app/lambda/springboot をマウントしておく想定。
# SPRING_BOOT_JAR="${SPRING_BOOT_JAR:-/app/lambda/springboot/musicflows-0.0.1-SNAPSHOT.jar}"
# 現在はbootJarではなく、docker-compose.ymlがマウントする
# ./backend/build/distributions内のLambda専用ZIPを使用する。
API_LAMBDA_ZIP="${API_LAMBDA_ZIP:-/app/lambda/springboot/musicflows-api-lambda.zip}"

# Worker Lambda用ZIPのFlociコンテナ内パス。
WORKER_LAMBDA_ZIP="${WORKER_LAMBDA_ZIP:-/app/lambda/springboot/musicflows-worker-lambda.zip}"

# 実際の Spring Boot Lambda Handler。
API_HANDLER="${API_HANDLER:-com.jws.musicflows.lambda.ApiGatewayLambdaHandler}"

# Worker Lambda の設定。
WORKER_HANDLER="org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
# Worker Lambda のメインクラス。
WORKER_MAIN_CLASS="com.jws.musicworker.WorkerFunctionApplication"

log "Lambda" "Initialization started."

COGNITO_USER_POOL_ID="$(
  get_ssm_parameter \
    "${PARAMETER_PREFIX}/cognito-user-pool-id"
)"

COGNITO_APP_CLIENT_ID="$(
  get_ssm_parameter \
    "${PARAMETER_PREFIX}/cognito-app-client-id"
)"

# JWTのiss claimと比較する値。
# Flociが発行するJWTでは、現在 http://localhost:4566/<UserPoolId>
# がissとして設定されているため、ホスト側URLを使用する。
#
# この値はJWTのclaim検証に使うだけなので、LambdaからlocalhostへHTTPアクセスする必要はない。

COGNITO_ISSUER_URI="${AWS_EDGE_HOST_URL}/${COGNITO_USER_POOL_ID}"

# JWT署名検証用JWKS。
#
# こちらはLambda実行コンテナから実際にHTTPアクセスする必要がある。
#
# Lambdaコンテナ内のlocalhostはFlociではないため、Docker内部URL http://floci:4566 を使用する。
COGNITO_JWK_SET_URI="${AWS_EDGE_INTERNAL_URL}/${COGNITO_USER_POOL_ID}/.well-known/jwks.json"


create_api_environment_json_value() {
  python3 - <<PY
import json

environment = {
    "Variables": {
        "SPRING_PROFILES_ACTIVE": "lambda",
        "AWS_REGION": "${AWS_REGION}",
        "AWS_ENDPOINT_URL": "${AWS_EDGE_INTERNAL_URL}",
        "SQS_QUEUE_NAME": "${QUEUE_NAME}",
        "FILE_BUCKET": "${FILE_BUCKET}",
        "FRONTEND_ORIGIN": "${FRONTEND_ORIGIN}",
        "COGNITO_ISSUER_URI": "${COGNITO_ISSUER_URI}",
        "COGNITO_JWK_SET_URI": "${COGNITO_JWK_SET_URI}",
        "COGNITO_APP_CLIENT_ID": "${COGNITO_APP_CLIENT_ID}",
        "DB_SECRET_NAME": "${SECRET_NAME}"
    }
}

print(json.dumps(environment))
PY
}

create_worker_environment_json_value() {

  python3 - <<PY
import json

environment = {
    "Variables": {

        "SPRING_PROFILES_ACTIVE": "worker-lambda",
        "MAIN_CLASS": "${WORKER_MAIN_CLASS}",
        "spring_cloud_function_definition": "musicJobWorker",
        "AWS_REGION": "${AWS_REGION}",
        "AWS_ENDPOINT_URL": "${AWS_EDGE_INTERNAL_URL}",
        "FILE_BUCKET": "${FILE_BUCKET}"
    }
}

print(json.dumps(environment))
PY
}

wait_api_function_updated() {
  aws_local lambda wait function-updated-v2 \
    --function-name "${API_FUNCTION_NAME}" \
    >/dev/null 2>&1 || true
}

# Worker Lambdaのコードまたは設定更新が完了するまで待機する。
# update-function-code直後の設定更新や、後続のEvent Source Mapping設定との競合を防ぐ。
wait_worker_function_updated() {
  aws_local lambda wait function-updated-v2 \
    --function-name "${WORKER_FUNCTION_NAME}" \
    >/dev/null 2>&1 || true
}


create_or_update_api_alias() {
  function_version="$1"

  if aws_local lambda get-alias \
    --function-name "${API_FUNCTION_NAME}" \
    --name "${API_FUNCTION_ALIAS_NAME}" \
    >/dev/null 2>&1; then

    aws_local lambda update-alias \
      --function-name "${API_FUNCTION_NAME}" \
      --name "${API_FUNCTION_ALIAS_NAME}" \
      --function-version "${function_version}" \
      >/dev/null

    log "Lambda" "API alias updated: ${API_FUNCTION_ALIAS_NAME} -> version ${function_version}"
  else
    aws_local lambda create-alias \
      --function-name "${API_FUNCTION_NAME}" \
      --name "${API_FUNCTION_ALIAS_NAME}" \
      --function-version "${function_version}" \
      >/dev/null

    log "Lambda" "API alias created: ${API_FUNCTION_ALIAS_NAME} -> version ${function_version}"
  fi
}

publish_api_function_version_and_update_alias() {
  wait_api_function_updated

  published_version="$(aws_local lambda publish-version \
    --function-name "${API_FUNCTION_NAME}" \
    --query Version \
    --output text)"

  create_or_update_api_alias "${published_version}"
}

# Lambdaのデプロイ成果物をS3にアップロードする。
# API LambdaとWorker Lambdaで異なるZIPを使用するため、
# ローカルパスとS3キーを引数で受け取る。
upload_lambda_artifact() {
  artifact_path="$1"
  artifact_key="$2"

  # Lambda ZIPが存在しない場合は、Gradleでビルドしていない可能性があるので、エラーとして処理する。
  if [ ! -f "${artifact_path}" ]; then
    log "Lambda" "Lambda ZIP not found: ${artifact_path}"
    return 1
  fi

  log "Lambda" "Uploading Lambda artifact to S3: s3://${LAMBDA_ARTIFACT_BUCKET}/${artifact_key}"

  # Lambda ZIPをS3にアップロードする。
  aws_local s3api put-object \
    --bucket "${LAMBDA_ARTIFACT_BUCKET}" \
    --key "${artifact_key}" \
    --body "${artifact_path}" \
    >/dev/null

  log "Lambda" "Lambda artifact uploaded: ${artifact_key}"
}

# API Gateway と Lambda の疎通確認を目的とした仮実装
# React の開発サーバーから API を呼び出せるように、CORS ヘッダーも含める。
create_or_update_spring_api_function() {
  # API Lambda専用ZIPが存在することを確認する。
  if [ ! -f "${API_LAMBDA_ZIP}" ]; then
    log "Lambda" "API Lambda ZIP not found: ${API_LAMBDA_ZIP}"
    log "Lambda" "Skip API Lambda creation. Run './gradlew clean buildApiLambdaZip' first."
    return 1
  fi

  API_LAMBDA_ENVIRONMENT_JSON="$(create_api_environment_json_value)"

  # API Lambda が存在するか確認し、存在すれば更新、存在しなければ作成する。
  if aws_local lambda get-function \
      --function-name "${API_FUNCTION_NAME}" \
      >/dev/null 2>&1; then
    
     # LambdaのコードをS3から更新する場合は、S3にアップロード済みである必要がある。
     aws_local lambda update-function-code \
      --function-name "${API_FUNCTION_NAME}" \
      --s3-bucket "${LAMBDA_ARTIFACT_BUCKET}" \
      --s3-key "${API_LAMBDA_ARTIFACT_KEY}" \
      >/dev/null

    # コード更新完了後にLambdaの設定を更新する。
    wait_api_function_updated

    # Lambdaの設定を更新する。
    aws_local lambda update-function-configuration \
      --function-name "${API_FUNCTION_NAME}" \
      --runtime java25 \
      --handler "${API_HANDLER}" \
      --timeout 60 \
      --memory-size 1024 \
      --environment "${API_LAMBDA_ENVIRONMENT_JSON}" \
      --snap-start ApplyOn=PublishedVersions \
      >/dev/null

    log "Lambda" "Spring Boot API function updated: ${API_FUNCTION_NAME}"
  else
    
    # LambdaのコードをS3から作成する場合は、S3にアップロード済みである必要がある。
    aws_local lambda create-function \
      --function-name "${API_FUNCTION_NAME}" \
      --runtime java25 \
      --role "${LAMBDA_ROLE_ARN}" \
      --handler "${API_HANDLER}" \
      --code \
        "S3Bucket=${LAMBDA_ARTIFACT_BUCKET},S3Key=${API_LAMBDA_ARTIFACT_KEY}" \
      --timeout 60 \
      --memory-size 1024 \
      --environment "${API_LAMBDA_ENVIRONMENT_JSON}" \
      --snap-start ApplyOn=PublishedVersions \
      >/dev/null

    log "Lambda" "Spring Boot API function created: ${API_FUNCTION_NAME}"
  fi

  publish_api_function_version_and_update_alias
}

# Worker Lambda の実装
create_or_update_worker_function() {
  # Worker Lambda専用ZIPが存在することを確認する。
  if [ ! -f "${WORKER_LAMBDA_ZIP}" ]; then
    log "Lambda" "Worker Lambda ZIP not found: ${WORKER_LAMBDA_ZIP}"
    log "Lambda" "Skip Worker Lambda creation. Run './gradlew clean buildWorkerLambdaZip' first."
    return 1
  fi

  WORKER_ENVIRONMENT_JSON="$(
    create_worker_environment_json_value
  )"

  # Worker Lambda が存在するか確認し、存在すれば更新、存在しなければ作成する。
  if aws_local lambda get-function \
      --function-name "${WORKER_FUNCTION_NAME}" \
      >/dev/null 2>&1; then

    # LambdaのコードをS3から更新する場合は、S3にアップロード済みである必要がある。
    aws_local lambda update-function-code \
      --function-name "${WORKER_FUNCTION_NAME}" \
      --s3-bucket "${LAMBDA_ARTIFACT_BUCKET}" \
      --s3-key "${WORKER_LAMBDA_ARTIFACT_KEY}" \
      >/dev/null

    # コード更新完了後にWorker Lambdaの設定を更新する。
    wait_worker_function_updated

    aws_local lambda update-function-configuration \
      --function-name "${WORKER_FUNCTION_NAME}" \
      --runtime java25 \
      --handler "${WORKER_HANDLER}" \
      --timeout 30 \
      --memory-size 512 \
      --environment "${WORKER_ENVIRONMENT_JSON}" \
      >/dev/null

    # 後続のEvent Source Mapping設定より前に、Worker Lambdaの設定更新完了を待つ。
    wait_worker_function_updated

    log "Lambda" \
      "Spring Cloud Function Worker updated: ${WORKER_FUNCTION_NAME}"

  else

    # LambdaのコードをS3から作成する場合は、S3にアップロード済みである必要がある。
    aws_local lambda create-function \
       --function-name "${WORKER_FUNCTION_NAME}" \
       --runtime java25 \
       --role "${LAMBDA_ROLE_ARN}" \
       --handler "${WORKER_HANDLER}" \
       --code \
         "S3Bucket=${LAMBDA_ARTIFACT_BUCKET},S3Key=${WORKER_LAMBDA_ARTIFACT_KEY}" \
       --timeout 30 \
       --memory-size 512 \
       --environment "${WORKER_ENVIRONMENT_JSON}" \
       >/dev/null

    log "Lambda" \
      "Spring Cloud Function Worker created: ${WORKER_FUNCTION_NAME}"
  fi
}

# ------------------------------------------------------------
# Lambda ZIPを先にS3へ配置する。
# API / WorkerのLambda APIへ巨大なBase64を直接送らない。
# ------------------------------------------------------------
# API Lambda専用ZIPをアップロードする。
upload_lambda_artifact \
  "${API_LAMBDA_ZIP}" \
  "${API_LAMBDA_ARTIFACT_KEY}"

# Worker Lambda専用ZIPをアップロードする。
upload_lambda_artifact \
  "${WORKER_LAMBDA_ZIP}" \
  "${WORKER_LAMBDA_ARTIFACT_KEY}"


# ------------------------------------------------------------
# S3上の成果物からLambdaを作成・更新する。
# ------------------------------------------------------------
# API LambdaはAPI専用ZIPから作成・更新する。
create_or_update_spring_api_function

# Worker LambdaはWorker専用ZIPから作成・更新する。
create_or_update_worker_function


log "Lambda" "Initialization completed."
