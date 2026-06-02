#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

REST_API_NAME="${PROJECT_NAME}-${ENVIRONMENT}-api"
AUTHORIZER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-cognito-authorizer"
API_FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-api-handler"

PARAMETER_PREFIX="/${PROJECT_NAME}/${ENVIRONMENT}"
ACCOUNT_ID="000000000000"
STAGE_NAME="local"

echo "[API Gateway] Initialization started."

# API Gateway 用の Lambda 関数の ZIP ファイルパス
USER_POOL_ID="$(aws ssm get-parameter \
  --name "${PARAMETER_PREFIX}/cognito-user-pool-id" \
  --query Parameter.Value \
  --output text)"

# Lambda 関数のコードを格納する一時ディレクトリ
USER_POOL_ARN="arn:aws:cognito-idp:${AWS_REGION}:${ACCOUNT_ID}:userpool/${USER_POOL_ID}"
API_FUNCTION_ARN="arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${API_FUNCTION_NAME}"
INTEGRATION_URI="arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${API_FUNCTION_ARN}/invocations"

# API Gateway の REST API を作成または取得
API_ID="$(aws apigateway get-rest-apis \
  --query "items[?name=='${REST_API_NAME}'].id | [0]" \
  --output text)"

# REST API が存在しない場合は作成
if [ "${API_ID}" = "None" ] || [ -z "${API_ID}" ]; then
  API_ID="$(aws apigateway create-rest-api \
    --name "${REST_API_NAME}" \
    --query id \
    --output text)"

  echo "[API Gateway] REST API created: ${REST_API_NAME}"
else
  echo "[API Gateway] REST API already exists: ${REST_API_NAME}"
fi

# ルートリソースの ID を取得
ROOT_RESOURCE_ID="$(aws apigateway get-resources \
  --rest-api-id "${API_ID}" \
  --query "items[?path=='/'].id | [0]" \
  --output text)"

# 指定されたパスにリソースが存在しない場合は作成する関数
get_or_create_resource() {
  PARENT_ID="$1"
  PATH_PART="$2"
  FULL_PATH="$3"

  RESOURCE_ID="$(aws apigateway get-resources \
    --rest-api-id "${API_ID}" \
    --query "items[?path=='${FULL_PATH}'].id | [0]" \
    --output text)"

  if [ "${RESOURCE_ID}" = "None" ] || [ -z "${RESOURCE_ID}" ]; then
    RESOURCE_ID="$(aws apigateway create-resource \
      --rest-api-id "${API_ID}" \
      --parent-id "${PARENT_ID}" \
      --path-part "${PATH_PART}" \
      --query id \
      --output text)"
  fi

  echo "${RESOURCE_ID}"
}

# ワークディレクトリの準備
API_RESOURCE_ID="$(get_or_create_resource "${ROOT_RESOURCE_ID}" "api" "/api")"
HEALTH_RESOURCE_ID="$(get_or_create_resource "${API_RESOURCE_ID}" "health" "/api/health")"
PROJECTS_RESOURCE_ID="$(get_or_create_resource "${API_RESOURCE_ID}" "projects" "/api/projects")"

# 仮の Lambda ハンドラーコードを作成 (後で本格的なコードに置き換える予定)
AUTHORIZER_ID="$(aws apigateway get-authorizers \
  --rest-api-id "${API_ID}" \
  --query "items[?name=='${AUTHORIZER_NAME}'].id | [0]" \
  --output text)"

if [ "${AUTHORIZER_ID}" = "None" ] || [ -z "${AUTHORIZER_ID}" ]; then
  AUTHORIZER_ID="$(aws apigateway create-authorizer \
    --rest-api-id "${API_ID}" \
    --name "${AUTHORIZER_NAME}" \
    --type COGNITO_USER_POOLS \
    --provider-arns "${USER_POOL_ARN}" \
    --identity-source "method.request.header.Authorization" \
    --query id \
    --output text)"

  echo "[API Gateway] Cognito authorizer created: ${AUTHORIZER_NAME}"
else
  echo "[API Gateway] Cognito authorizer already exists: ${AUTHORIZER_NAME}"
fi

# GET /api/health: 認証なし
aws apigateway delete-method \
  --rest-api-id "${API_ID}" \
  --resource-id "${HEALTH_RESOURCE_ID}" \
  --http-method GET \
  >/dev/null 2>&1 || true

# GET /api/health: 認証なし
aws apigateway put-method \
  --rest-api-id "${API_ID}" \
  --resource-id "${HEALTH_RESOURCE_ID}" \
  --http-method GET \
  --authorization-type NONE \
  >/dev/null

# GET /api/health: Lambda 統合
aws apigateway put-integration \
  --rest-api-id "${API_ID}" \
  --resource-id "${HEALTH_RESOURCE_ID}" \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "${INTEGRATION_URI}" \
  >/dev/null

# GET /api/projects: Cognito 認証あり
aws apigateway delete-method \
  --rest-api-id "${API_ID}" \
  --resource-id "${PROJECTS_RESOURCE_ID}" \
  --http-method GET \
  >/dev/null 2>&1 || true

# GET /api/projects: Cognito 認証あり
aws apigateway put-method \
  --rest-api-id "${API_ID}" \
  --resource-id "${PROJECTS_RESOURCE_ID}" \
  --http-method GET \
  --authorization-type COGNITO_USER_POOLS \
  --authorizer-id "${AUTHORIZER_ID}" \
  >/dev/null

# GET /api/projects: Lambda 統合
aws apigateway put-integration \
  --rest-api-id "${API_ID}" \
  --resource-id "${PROJECTS_RESOURCE_ID}" \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "${INTEGRATION_URI}" \
  >/dev/null

# API Gateway が Lambda を呼び出せるように権限を設定
aws lambda remove-permission \
  --function-name "${API_FUNCTION_NAME}" \
  --statement-id "allow-api-gateway-invoke" \
  >/dev/null 2>&1 || true

# API Gateway が Lambda を呼び出せるように権限を設定
aws lambda add-permission \
  --function-name "${API_FUNCTION_NAME}" \
  --statement-id "allow-api-gateway-invoke" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${ACCOUNT_ID}:${API_ID}/*/*/*" \
  >/dev/null

# API をデプロイ
aws apigateway create-deployment \
  --rest-api-id "${API_ID}" \
  --stage-name "${STAGE_NAME}" \
  >/dev/null

# API のエンドポイント URL を SSM パラメータストアに保存
API_BASE_URL_HOST="http://localhost:4566/restapis/${API_ID}/${STAGE_NAME}/_user_request_"
API_BASE_URL_INTERNAL="http://floci:4566/restapis/${API_ID}/${STAGE_NAME}/_user_request_"

# API ID とエンドポイント URL を SSM パラメータストアに保存
aws ssm put-parameter \
  --name "${PARAMETER_PREFIX}/api-id" \
  --type String \
  --value "${API_ID}" \
  --overwrite \
  >/dev/null

# API のエンドポイント URL を SSM パラメータストアに保存
aws ssm put-parameter \
  --name "${PARAMETER_PREFIX}/api-base-url-host" \
  --type String \
  --value "${API_BASE_URL_HOST}" \
  --overwrite \
  >/dev/null

# API のエンドポイント URL を SSM パラメータストアに保存
aws ssm put-parameter \
  --name "${PARAMETER_PREFIX}/api-base-url-internal" \
  --type String \
  --value "${API_BASE_URL_INTERNAL}" \
  --overwrite \
  >/dev/null

echo "[API Gateway] Route prepared: GET /api/health"
echo "[API Gateway] Route prepared: GET /api/projects"
echo "[API Gateway] Host URL: ${API_BASE_URL_HOST}"
echo "[API Gateway] Initialization completed."