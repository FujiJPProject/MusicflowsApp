#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "API Gateway" "Initialization started."

USER_POOL_ID="$(get_ssm_parameter "${PARAMETER_PREFIX}/cognito-user-pool-id")"
USER_POOL_ARN="arn:aws:cognito-idp:${AWS_REGION}:${AWS_ACCOUNT_ID}:userpool/${USER_POOL_ID}"
API_FUNCTION_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${API_FUNCTION_NAME}"
INTEGRATION_URI="arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${API_FUNCTION_ARN}/invocations"

#   Rest API の作成 (存在しない場合)
API_ID="$(aws apigateway get-rest-apis \
  --query "items[?name=='${REST_API_NAME}'].id | [0]" \
  --output text)"

if is_missing_aws_value "${API_ID}"; then
  API_ID="$(aws apigateway create-rest-api \
    --name "${REST_API_NAME}" \
    --query id \
    --output text)"
  log "API Gateway" "REST API created: ${REST_API_NAME}"
else
  log "API Gateway" "REST API already exists: ${REST_API_NAME}"
fi

# ルート Resource ID の取得
ROOT_RESOURCE_ID="$(aws apigateway get-resources \
  --rest-api-id "${API_ID}" \
  --query "items[?path=='/'].id | [0]" \
  --output text)"

# API Gateway の Resource を 存在すれば再利用し、なければ作成する 関数
get_or_create_resource() {
  # 親 Resource ID (例: ルートリソースの ID, /api のリソース ID)
  parent_id="$1"
  # パスの一部 (例: "api", "health", "projects")
  path_part="$2"
    # フルパス (例: "/api", "/api/health", "/api/projects")
  full_path="$3"

  resource_id="$(aws apigateway get-resources \
    --rest-api-id "${API_ID}" \
    --query "items[?path=='${full_path}'].id | [0]" \
    --output text)"

  if is_missing_aws_value "${resource_id}"; then
    resource_id="$(aws apigateway create-resource \
      --rest-api-id "${API_ID}" \
      --parent-id "${parent_id}" \
      --path-part "${path_part}" \
      --query id \
      --output text)"
  fi

  printf '%s\n' "${resource_id}"
}

# 認証なし GET Route 設定関数
configure_public_get_route() {
  resource_id="$1"

  # 既存の GET メソッドを削除してから再作成する (冪等性の確保)
  aws apigateway delete-method \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method GET \
    >/dev/null 2>&1 || true

  # 認証なしの GET メソッドを作成
  aws apigateway put-method \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method GET \
    --authorization-type NONE \
    >/dev/null

  # 認証なしの GET メソッドに Lambda 統合を設定
  # API Gateway で Lambda プロキシ統合を使用する場合、統合タイプは AWS_PROXY となり、統合 HTTP メソッドは POST になります。
  aws apigateway put-integration \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "${INTEGRATION_URI}" \
    >/dev/null
}

# Cognito 認証付き GET Route 設定関数
configure_cognito_get_route() {
  resource_id="$1"
  authorizer_id="$2"

  # 既存の GET メソッドを削除してから再作成する (冪等性の確保)
  aws apigateway delete-method \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method GET \
    >/dev/null 2>&1 || true

  # Cognito 認証付きの GET メソッドを作成
  aws apigateway put-method \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method GET \
    --authorization-type COGNITO_USER_POOLS \
    --authorizer-id "${authorizer_id}" \
    >/dev/null

  # Cognito 認証付きの GET メソッドに Lambda 統合を設定
  aws apigateway put-integration \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "${INTEGRATION_URI}" \
    >/dev/null
}

# Resourceの作成
API_RESOURCE_ID="$(get_or_create_resource "${ROOT_RESOURCE_ID}" "api" "/api")"
HEALTH_RESOURCE_ID="$(get_or_create_resource "${API_RESOURCE_ID}" "health" "/api/health")"
PROJECTS_RESOURCE_ID="$(get_or_create_resource "${API_RESOURCE_ID}" "projects" "/api/projects")"

# Cognito Authorizer の作成 (存在しない場合)
AUTHORIZER_ID="$(aws apigateway get-authorizers \
  --rest-api-id "${API_ID}" \
  --query "items[?name=='${AUTHORIZER_NAME}'].id | [0]" \
  --output text)"

if is_missing_aws_value "${AUTHORIZER_ID}"; then
  AUTHORIZER_ID="$(aws apigateway create-authorizer \
    --rest-api-id "${API_ID}" \
    --name "${AUTHORIZER_NAME}" \
    --type COGNITO_USER_POOLS \
    --provider-arns "${USER_POOL_ARN}" \
    --identity-source "method.request.header.Authorization" \
    --query id \
    --output text)"
  log "API Gateway" "Cognito authorizer created: ${AUTHORIZER_NAME}"
else
  log "API Gateway" "Cognito authorizer already exists: ${AUTHORIZER_NAME}"
fi

# Route の設定
configure_public_get_route "${HEALTH_RESOURCE_ID}"
configure_cognito_get_route "${PROJECTS_RESOURCE_ID}" "${AUTHORIZER_ID}"

# Lamdbda 関数への API Gateway からの呼び出しを許可するための権限設定
# 既存の権限を削除してから再作成する (冪等性の確保)
aws lambda remove-permission \
  --function-name "${API_FUNCTION_NAME}" \
  --statement-id "allow-api-gateway-invoke" \
  >/dev/null 2>&1 || true

# API Gateway から Lambda 関数を呼び出すための権限を追加
# --function-name には Lambda 関数の名前を指定
# --source-arn には API Gateway の ARN を指定。
# --action には lambda:InvokeFunction を指定して、API Gateway が Lambda 関数を呼び出すことを許可する。
# --principal には apigateway.amazonaws.com を指定して、API Gateway サービスからの呼び出しを許可する。
# API Gateway の ARN は、arn:aws:execute-api:{region}:{account_id}:{api_id}/{stage_name}/{http_method}/{resource_path} という形式になる。
aws lambda add-permission \
  --function-name "${API_FUNCTION_NAME}" \
  --statement-id "allow-api-gateway-invoke" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*/*" \
  >/dev/null

# API をデプロイして変更を反映
aws apigateway create-deployment \
  --rest-api-id "${API_ID}" \
  --stage-name "${STAGE_NAME}" \
  >/dev/null

# API URL の構築と SSM パラメータへの保存
API_BASE_URL_HOST="${AWS_EDGE_HOST_URL}/restapis/${API_ID}/${STAGE_NAME}/_user_request_"
API_BASE_URL_INTERNAL="${AWS_EDGE_INTERNAL_URL}/restapis/${API_ID}/${STAGE_NAME}/_user_request_"

put_ssm_parameter "${PARAMETER_PREFIX}/api-id" "${API_ID}"
put_ssm_parameter "${PARAMETER_PREFIX}/api-base-url-host" "${API_BASE_URL_HOST}"
put_ssm_parameter "${PARAMETER_PREFIX}/api-base-url-internal" "${API_BASE_URL_INTERNAL}"

log "API Gateway" "Route prepared: GET /api/health"
log "API Gateway" "Route prepared: GET /api/projects"
log "API Gateway" "Host URL: ${API_BASE_URL_HOST}"
log "API Gateway" "Initialization completed."
