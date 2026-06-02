#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"

USER_POOL_NAME="${PROJECT_NAME}-${ENVIRONMENT}-users"
APP_CLIENT_NAME="${PROJECT_NAME}-${ENVIRONMENT}-web-client"

TEST_USERNAME="local-user@example.com"
TEST_PASSWORD="LocalPass123!"

PARAMETER_PREFIX="/${PROJECT_NAME}/${ENVIRONMENT}"

echo "[Cognito] Initialization started."

# Cognito ユーザープールの作成
USER_POOL_ID="$(aws cognito-idp list-user-pools \
  --max-results 60 \
  --query "UserPools[?Name=='${USER_POOL_NAME}'].Id | [0]" \
  --output text)"

# ユーザープールが存在しない場合は作成
if [ "${USER_POOL_ID}" = "None" ] || [ -z "${USER_POOL_ID}" ]; then
  USER_POOL_ID="$(aws cognito-idp create-user-pool \
    --pool-name "${USER_POOL_NAME}" \
    --query UserPool.Id \
    --output text)"

  echo "[Cognito] User pool created: ${USER_POOL_NAME}"
else
  echo "[Cognito] User pool already exists: ${USER_POOL_NAME}"
fi

# Cognito アプリクライアントの作成
APP_CLIENT_ID="$(aws cognito-idp list-user-pool-clients \
  --user-pool-id "${USER_POOL_ID}" \
  --max-results 60 \
  --query "UserPoolClients[?ClientName=='${APP_CLIENT_NAME}'].ClientId | [0]" \
  --output text)"

# アプリクライアントが存在しない場合は作成
if [ "${APP_CLIENT_ID}" = "None" ] || [ -z "${APP_CLIENT_ID}" ]; then
  APP_CLIENT_ID="$(aws cognito-idp create-user-pool-client \
    --user-pool-id "${USER_POOL_ID}" \
    --client-name "${APP_CLIENT_NAME}" \
    --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
    --query UserPoolClient.ClientId \
    --output text)"

  echo "[Cognito] App client created: ${APP_CLIENT_NAME}"
else
  echo "[Cognito] App client already exists: ${APP_CLIENT_NAME}"
fi

# テストユーザーの作成
if aws cognito-idp admin-get-user \
  --user-pool-id "${USER_POOL_ID}" \
  --username "${TEST_USERNAME}" \
  >/dev/null 2>&1; then
  echo "[Cognito] Test user already exists: ${TEST_USERNAME}"
else
  # ユーザーが存在しない場合は作成
  aws cognito-idp admin-create-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "${TEST_USERNAME}" \
    --temporary-password "${TEST_PASSWORD}" \
    >/dev/null

  echo "[Cognito] Test user created: ${TEST_USERNAME}"
fi

# テストユーザーのパスワードを永続化
aws cognito-idp admin-set-user-password \
  --user-pool-id "${USER_POOL_ID}" \
  --username "${TEST_USERNAME}" \
  --password "${TEST_PASSWORD}" \
  --permanent \
  >/dev/null

# SSM パラメータストアに Cognito のユーザープールIDとアプリクライアントIDを保存
aws ssm put-parameter \
  --name "${PARAMETER_PREFIX}/cognito-user-pool-id" \
  --type String \
  --value "${USER_POOL_ID}" \
  --overwrite \
  >/dev/null

# SSM パラメータストアに Cognito のアプリクライアントIDを保存
aws ssm put-parameter \
  --name "${PARAMETER_PREFIX}/cognito-app-client-id" \
  --type String \
  --value "${APP_CLIENT_ID}" \
  --overwrite \
  >/dev/null

echo "[Cognito] User Pool ID: ${USER_POOL_ID}"
echo "[Cognito] App Client ID: ${APP_CLIENT_ID}"
echo "[Cognito] Initialization completed."