#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"
PARAMETER_PREFIX="/${PROJECT_NAME}/${ENVIRONMENT}"

OUTPUT_DIR="/app/export/frontend-config"
OUTPUT_FILE="${OUTPUT_DIR}/local-config.json"

echo "[Frontend Config] Export started."

mkdir -p "${OUTPUT_DIR}"

# SSM パラメータストアから API エンドポイント URL と Cognito 設定を取得
API_BASE_URL="$(aws ssm get-parameter \
  --name "${PARAMETER_PREFIX}/api-base-url-host" \
  --query Parameter.Value \
  --output text)"

# SSM パラメータストアから Cognito ユーザープール ID とアプリクライアント ID を取得
USER_POOL_ID="$(aws ssm get-parameter \
  --name "${PARAMETER_PREFIX}/cognito-user-pool-id" \
  --query Parameter.Value \
  --output text)"

# SSM パラメータストアから Cognito アプリクライアント ID を取得
APP_CLIENT_ID="$(aws ssm get-parameter \
  --name "${PARAMETER_PREFIX}/cognito-app-client-id" \
  --query Parameter.Value \
  --output text)"

# フロントエンドで使用する設定を JSON ファイルに出力
cat > "${OUTPUT_FILE}" <<EOF
{
  "apiBaseUrl": "${API_BASE_URL}",
  "cognitoUserPoolId": "${USER_POOL_ID}",
  "cognitoClientId": "${APP_CLIENT_ID}",
  "awsRegion": "ap-northeast-1",
  "cognitoEndpointUrl": "http://localhost:4566"
}
EOF

echo "[Frontend Config] File created: ${OUTPUT_FILE}"
echo "[Frontend Config] Export completed."