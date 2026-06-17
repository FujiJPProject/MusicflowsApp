#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "API Gateway" "Initialization started."

API_FUNCTION_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${API_FUNCTION_NAME}"
INTEGRATION_URI="arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${API_FUNCTION_ARN}/invocations"

# REST API の作成または取得
API_ID="$(aws_local apigateway get-rest-apis \
  --query "items[?name=='${REST_API_NAME}'].id | [0]" \
  --output text)"

if is_missing_aws_value "${API_ID}"; then
  API_ID="$(aws_local apigateway create-rest-api \
    --name "${REST_API_NAME}" \
    --query id \
    --output text)"
  log "API Gateway" "REST API created: ${REST_API_NAME}"
else
  log "API Gateway" "REST API already exists: ${REST_API_NAME}"
fi

# ルート Resource ID の取得
ROOT_RESOURCE_ID="$(aws_local apigateway get-resources \
  --rest-api-id "${API_ID}" \
  --query "items[?path=='/'].id | [0]" \
  --output text)"

# API Gateway の Resource を存在すれば再利用し、なければ作成する関数
get_or_create_resource() {
  parent_id="$1"
  path_part="$2"
  full_path="$3"

  resource_id="$(aws_local apigateway get-resources \
    --rest-api-id "${API_ID}" \
    --query "items[?path=='${full_path}'].id | [0]" \
    --output text)"

  if is_missing_aws_value "${resource_id}"; then
    resource_id="$(aws_local apigateway create-resource \
      --rest-api-id "${API_ID}" \
      --parent-id "${parent_id}" \
      --path-part "${path_part}" \
      --query id \
      --output text)"
    log "API Gateway" "Resource created: ${full_path}" >&2
  else
    log "API Gateway" "Resource already exists: ${full_path}" >&2
  fi

  printf '%s\n' "${resource_id}"
}

# Lambda プロキシ統合用の ANY Route を設定する関数
configure_lambda_proxy_any_route() {
  resource_id="$1"

  # 既存の ANY メソッドを削除してから再作成する。
  # これにより、スクリプトを複数回実行しても設定のズレが残りにくくなる。
  aws_local apigateway delete-method \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method ANY \
    >/dev/null 2>&1 || true

  # 認証は API Gateway ではなく Spring Security 側で制御する。
  # Floci の Cognito Authorizer 互換性に依存しない構成にするため、ここでは NONE にする。
  aws_local apigateway put-method \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method ANY \
    --authorization-type NONE \
    >/dev/null

  # Spring Boot Lambda へ Lambda プロキシ統合する。
  # API Gateway の Lambda プロキシ統合では integration-http-method は POST を指定する。
  aws_local apigateway put-integration \
    --rest-api-id "${API_ID}" \
    --resource-id "${resource_id}" \
    --http-method ANY \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "${INTEGRATION_URI}" \
    >/dev/null

  log "API Gateway" "Route prepared: ANY /{proxy+}"
}

# /{proxy+} Resource を作成する。
# Spring Boot 側の Controller にルーティングを集約するため、
# API Gateway 側では個別の /api/health や /api/projects を作らない。
PROXY_RESOURCE_ID="$(get_or_create_resource "${ROOT_RESOURCE_ID}" "{proxy+}" "/{proxy+}")"
configure_lambda_proxy_any_route "${PROXY_RESOURCE_ID}"

# Lambda 関数への API Gateway からの呼び出しを許可するための権限設定
# 既存の権限を削除してから再作成する。
aws_local lambda remove-permission \
  --function-name "${API_FUNCTION_NAME}" \
  --statement-id "allow-api-gateway-invoke" \
  >/dev/null 2>&1 || true

aws_local lambda add-permission \
  --function-name "${API_FUNCTION_NAME}" \
  --statement-id "allow-api-gateway-invoke" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*/*" \
  >/dev/null

# API をデプロイして変更を反映
DEPLOYMENT_ID="$(aws_local apigateway create-deployment \
  --rest-api-id "${API_ID}" \
  --query id \
  --output text)"

# Floci では create-deployment --stage-name だけでは stage が作成されない場合があるため、
# stage を明示的に作成し直す。
aws_local apigateway delete-stage \
  --rest-api-id "${API_ID}" \
  --stage-name "${STAGE_NAME}" \
  >/dev/null 2>&1 || true

aws_local apigateway create-stage \
  --rest-api-id "${API_ID}" \
  --stage-name "${STAGE_NAME}" \
  --deployment-id "${DEPLOYMENT_ID}" \
  >/dev/null

# API URL の構築と SSM パラメータへの保存
# 09-export-frontend-config.sh がこの値を取得して React 用 config JSON を出力する。
API_BASE_URL_HOST="${AWS_EDGE_HOST_URL}/restapis/${API_ID}/${STAGE_NAME}/_user_request_"
API_BASE_URL_INTERNAL="${AWS_EDGE_INTERNAL_URL}/restapis/${API_ID}/${STAGE_NAME}/_user_request_"

put_ssm_parameter "${PARAMETER_PREFIX}/api-id" "${API_ID}"
put_ssm_parameter "${PARAMETER_PREFIX}/api-base-url-host" "${API_BASE_URL_HOST}"
put_ssm_parameter "${PARAMETER_PREFIX}/api-base-url-internal" "${API_BASE_URL_INTERNAL}"

log "API Gateway" "Host URL: ${API_BASE_URL_HOST}"
log "API Gateway" "Initialization completed."