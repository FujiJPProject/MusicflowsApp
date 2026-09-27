#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "Frontend Config" "Export started."

validate_worker_execution_mode

OUTPUT_DIR="${FRONTEND_CONFIG_OUTPUT_DIR}"
OUTPUT_FILE="${OUTPUT_DIR}/local-config.json"

echo "[Frontend Config] Export started."

mkdir -p "${OUTPUT_DIR}"

# SSM パラメータストアから API エンドポイント URL と Cognito 設定を取得
API_BASE_URL="$(
  get_ssm_parameter \
    "${PARAMETER_PREFIX}/api-base-url-host"
)"

# SSM パラメータストアから Cognito ユーザープール ID とアプリクライアント ID を取得
USER_POOL_ID="$(
  get_ssm_parameter \
    "${PARAMETER_PREFIX}/cognito-user-pool-id"
)"

# SSM パラメータストアから Cognito アプリクライアント ID を取得
APP_CLIENT_ID="$(
  get_ssm_parameter \
    "${PARAMETER_PREFIX}/cognito-app-client-id"
)"

# フロントエンドで使用する設定を JSON ファイルに出力
cat > "${OUTPUT_FILE}" <<EOF
{
  "apiBaseUrl": "${API_BASE_URL}",
  "directApiBaseUrl": "http://localhost:8080",
  "cognitoUserPoolId": "${USER_POOL_ID}",
  "cognitoClientId": "${APP_CLIENT_ID}",
  "awsRegion": "${AWS_REGION}",
  "cognitoEndpointUrl": "http://localhost:4566",
  "workerExecutionMode": "${WORKER_EXECUTION_MODE}"
}
EOF

echo "[Frontend Config] Worker execution mode: ${WORKER_EXECUTION_MODE}"
echo "[Frontend Config] File created: ${OUTPUT_FILE}"
echo "[Frontend Config] Export completed."