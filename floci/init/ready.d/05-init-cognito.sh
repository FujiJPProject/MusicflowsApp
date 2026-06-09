#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

TEST_USERNAME="${TEST_USERNAME:-local-user@example.com}"
TEST_PASSWORD="${TEST_PASSWORD:-LocalPass123!}"

log "Cognito" "Initialization started."

# Cognito ユーザープールの検索
USER_POOL_ID="$(aws_local cognito-idp list-user-pools \
  --max-results 60 \
  --query "UserPools[?Name=='${USER_POOL_NAME}'].Id | [0]" \
  --output text)"

# Cognito ユーザープールの作成 (結果から User Pool ID を抽出して保存)
if is_missing_aws_value "${USER_POOL_ID}"; then
  USER_POOL_ID="$(aws_local cognito-idp create-user-pool \
    --pool-name "${USER_POOL_NAME}" \
    --query UserPool.Id \
    --output text)"
  log "Cognito" "User pool created: ${USER_POOL_NAME}"
else
  log "Cognito" "User pool already exists: ${USER_POOL_NAME}"
fi

# User Pool の中に、 App Client ID が存在するか確認
APP_CLIENT_ID="$(aws_local cognito-idp list-user-pool-clients \
  --user-pool-id "${USER_POOL_ID}" \
  --max-results 60 \
  --query "UserPoolClients[?ClientName=='${APP_CLIENT_NAME}'].ClientId | [0]" \
  --output text)"

# App Client が存在しない場合は作成、存在する場合はスキップして App Client ID を取得
if is_missing_aws_value "${APP_CLIENT_ID}"; then
  # メールアドレスとパスワードによるログイン,およびリフレッシュトークンの発行を許可する設定で App Client を作成
  APP_CLIENT_ID="$(aws_local cognito-idp create-user-pool-client \
    --user-pool-id "${USER_POOL_ID}" \
    --client-name "${APP_CLIENT_NAME}" \
    --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
    --query UserPoolClient.ClientId \
    --output text)"
  log "Cognito" "App client created: ${APP_CLIENT_NAME}"
else
  log "Cognito" "App client already exists: ${APP_CLIENT_NAME}"
fi

# テストユーザーの存在確認と作成
if aws_local cognito-idp admin-get-user \
  --user-pool-id "${USER_POOL_ID}" \
  --username "${TEST_USERNAME}" \
  >/dev/null 2>&1; then
  log "Cognito" "Test user already exists: ${TEST_USERNAME}"
else
  aws_local cognito-idp admin-create-user \
    --user-pool-id "${USER_POOL_ID}" \
    --username "${TEST_USERNAME}" \
    --temporary-password "${TEST_PASSWORD}" \
    >/dev/null
  log "Cognito" "Test user created: ${TEST_USERNAME}"
fi

# テストユーザーのパスワードを永続化
# Cognito では、admin-create-user コマンドでユーザーを作成すると、最初は一時的なパスワードが設定される。
# ユーザーは最初のログイン時にこのパスワードを変更する必要があるが、admin-set-user-password コマンドを使うと
# 管理者がユーザーのパスワードを永続化することができる。これにより、初回ログイン時のパスワード変更をスキップできる。
aws_local cognito-idp admin-set-user-password \
  --user-pool-id "${USER_POOL_ID}" \
  --username "${TEST_USERNAME}" \
  --password "${TEST_PASSWORD}" \
  --permanent \
  >/dev/null

# SSM パラメータストアに Cognito の情報を保存
put_ssm_parameter "${PARAMETER_PREFIX}/cognito-user-pool-id" "${USER_POOL_ID}"
put_ssm_parameter "${PARAMETER_PREFIX}/cognito-app-client-id" "${APP_CLIENT_ID}"

log "Cognito" "User Pool ID: ${USER_POOL_ID}"
log "Cognito" "App Client ID: ${APP_CLIENT_ID}"
log "Cognito" "Initialization completed."
