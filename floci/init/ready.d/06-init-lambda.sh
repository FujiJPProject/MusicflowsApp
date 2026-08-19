#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

# Spring Boot の bootJar 成果物。
# docker-compose.yml 側で ./backend/build/libs:/app/lambda/springboot をマウントしておく想定。
# SPRING_BOOT_JAR="${SPRING_BOOT_JAR:-/app/lambda/springboot/musicflows-0.0.1-SNAPSHOT.jar}"
SPRING_BOOT_LAMBDA_ZIP="${SPRING_BOOT_LAMBDA_ZIP:-/app/lambda/springboot/musicflows-lambda.zip}"

# 実際の Spring Boot Lambda Handler。
API_HANDLER="${API_HANDLER:-com.jws.musicflows.lambda.ApiGatewayLambdaHandler}"

# Lambda 関数のコードを格納する一時ディレクトリとファイルのパスを定義
WORK_DIR="${LAMBDA_WORK_DIR:-/tmp/music-app-lambda}"
WORKER_DIR="${WORK_DIR}/music-job-worker"
WORKER_ZIP="${WORK_DIR}/music-job-worker.zip"

log "Lambda" "Initialization started."

# 以前の作業領域を削除
rm -rf "${WORK_DIR}"
mkdir -p "${WORKER_DIR}"

create_api_environment_json_value() {
  python3 - <<PY
import json

environment = {
    "Variables": {
        "SPRING_PROFILES_ACTIVE": "lambda",
        "AWS_REGION": "${AWS_REGION}",
        "AWS_ENDPOINT_URL": "${AWS_EDGE_INTERNAL_URL}",
        "FRONTEND_ORIGIN": "${FRONTEND_ORIGIN}",
        "DB_SECRET_NAME": "${SECRET_NAME}",
        "DB_HOST": "postgres",
        "DB_PORT": "5432",
        "DB_NAME": "music_app",
        "DB_USERNAME": "app_user",
        "DB_PASSWORD": "app_password"
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

# API Gateway と Lambda の疎通確認を目的とした仮実装
# React の開発サーバーから API を呼び出せるように、CORS ヘッダーも含める。
create_or_update_spring_api_function() {
  if [ ! -f "${SPRING_BOOT_LAMBDA_ZIP}" ]; then
    log "Lambda" "Spring Boot JAR not found: ${SPRING_BOOT_LAMBDA_ZIP}"
    log "Lambda" "Skip API Lambda creation. Run './gradlew clean bootJar' first."
    return
  fi

  API_LAMBDA_ENVIRONMENT_JSON="$(create_api_environment_json_value)"

  if aws_local lambda get-function --function-name "${API_FUNCTION_NAME}" >/dev/null 2>&1; then
    aws_local lambda update-function-code \
      --function-name "${API_FUNCTION_NAME}" \
      --zip-file "fileb://${SPRING_BOOT_LAMBDA_ZIP}" \
      >/dev/null

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
    aws_local lambda create-function \
      --function-name "${API_FUNCTION_NAME}" \
      --runtime java25 \
      --role "${LAMBDA_ROLE_ARN}" \
      --handler "${API_HANDLER}" \
      --zip-file "fileb://${SPRING_BOOT_LAMBDA_ZIP}" \
      --timeout 60 \
      --memory-size 1024 \
      --environment "${API_LAMBDA_ENVIRONMENT_JSON}" \
      --snap-start ApplyOn=PublishedVersions \
      >/dev/null

    log "Lambda" "Spring Boot API function created: ${API_FUNCTION_NAME}"
  fi

  publish_api_function_version_and_update_alias
}

# Worker Lambda の仮実装
create_or_update_worker_function() {
  cat > "${WORKER_DIR}/index.mjs" <<'EOF'
export const handler = async (event) => {
  console.log("Received music job messages:", JSON.stringify(event));

  for (const record of event.Records ?? []) {
    console.log("Processing music job:", record.body);
  }

  return {
    batchItemFailures: []
  };
};
EOF

  python3 - "${WORKER_DIR}" "${WORKER_ZIP}" <<'PY'
import sys
import zipfile

worker_dir, worker_zip = sys.argv[1:]

with zipfile.ZipFile(worker_zip, "w", zipfile.ZIP_DEFLATED) as archive:
    archive.write(f"{worker_dir}/index.mjs", "index.mjs")
PY

  if aws_local lambda get-function --function-name "${WORKER_FUNCTION_NAME}" >/dev/null 2>&1; then
    aws_local lambda update-function-code \
      --function-name "${WORKER_FUNCTION_NAME}" \
      --zip-file "fileb://${WORKER_ZIP}" \
      >/dev/null
    log "Lambda" "Worker function code updated: ${WORKER_FUNCTION_NAME}"
  else
    aws_local lambda create-function \
      --function-name "${WORKER_FUNCTION_NAME}" \
      --runtime nodejs22.x \
      --role "${LAMBDA_ROLE_ARN}" \
      --handler index.handler \
      --zip-file "fileb://${WORKER_ZIP}" \
      --timeout 30 \
      --memory-size 256 \
      >/dev/null
    log "Lambda" "Worker function created: ${WORKER_FUNCTION_NAME}"
  fi
}

# API Gateway と Lambda の接続は、API Gateway のリソースとメソッドの設定で行うため、ここでは Lambda 関数の作成・更新のみを行う。
create_or_update_spring_api_function
create_or_update_worker_function

log "Lambda" "Initialization completed."
