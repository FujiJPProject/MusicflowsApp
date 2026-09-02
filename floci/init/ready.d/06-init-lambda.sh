#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

# ------------------------------------------------------------
# Lambdaデプロイ成果物
# ------------------------------------------------------------

LAMBDA_ARTIFACT_BUCKET="${FILE_BUCKET}"

API_LAMBDA_ARTIFACT_KEY="_lambda-artifacts/musicflows-lambda.zip"

WORKER_LAMBDA_ARTIFACT_KEY="${API_LAMBDA_ARTIFACT_KEY}"

# Spring Boot の bootJar 成果物。
# docker-compose.yml 側で ./backend/build/libs:/app/lambda/springboot をマウントしておく想定。
# SPRING_BOOT_JAR="${SPRING_BOOT_JAR:-/app/lambda/springboot/musicflows-0.0.1-SNAPSHOT.jar}"
SPRING_BOOT_LAMBDA_ZIP="${SPRING_BOOT_LAMBDA_ZIP:-/app/lambda/springboot/musicflows-lambda.zip}"

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
upload_lambda_artifact() {

  # Lambda ZIPが存在しない場合は、Gradleでビルドしていない可能性があるので、エラーとして処理する。
  if [ ! -f "${SPRING_BOOT_LAMBDA_ZIP}" ]; then
    log "Lambda" "Lambda ZIP not found: ${SPRING_BOOT_LAMBDA_ZIP}"
    return 1
  fi

  log "Lambda" "Uploading Lambda artifact to S3: s3://${LAMBDA_ARTIFACT_BUCKET}/${API_LAMBDA_ARTIFACT_KEY}"

  # Lambda ZIPをS3にアップロードする。
  aws_local s3api put-object \
    --bucket "${LAMBDA_ARTIFACT_BUCKET}" \
    --key "${API_LAMBDA_ARTIFACT_KEY}" \
    --body "${SPRING_BOOT_LAMBDA_ZIP}" \
    >/dev/null

  log "Lambda" "Lambda artifact uploaded."
}

# API Gateway と Lambda の疎通確認を目的とした仮実装
# React の開発サーバーから API を呼び出せるように、CORS ヘッダーも含める。
create_or_update_spring_api_function() {
  if [ ! -f "${SPRING_BOOT_LAMBDA_ZIP}" ]; then
    log "Lambda" "Spring Boot JAR not found: ${SPRING_BOOT_LAMBDA_ZIP}"
    log "Lambda" "Skip API Lambda creation. Run './gradlew clean bootJar' first."
    return
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

    aws_local lambda update-function-configuration \
      --function-name "${WORKER_FUNCTION_NAME}" \
      --runtime java25 \
      --handler "${WORKER_HANDLER}" \
      --timeout 30 \
      --memory-size 512 \
      --environment "${WORKER_ENVIRONMENT_JSON}" \
      >/dev/null

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
upload_lambda_artifact


# ------------------------------------------------------------
# S3上の成果物からLambdaを作成・更新する。
# ------------------------------------------------------------
create_or_update_spring_api_function

create_or_update_worker_function


log "Lambda" "Initialization completed."