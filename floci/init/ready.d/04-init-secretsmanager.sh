#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"

SECRET_NAME="${PROJECT_NAME}/${ENVIRONMENT}/db"

# データベース接続情報を Secrets Manager に保存
SECRET_VALUE='{
  "host": "postgres",
  "port": "5432",
  "dbname": "music_app",
  "username": "app_user",
  "password": "app_password"
}'

echo "[Secrets Manager] Initialization started."

# シークレットが既に存在するか確認
if aws secretsmanager describe-secret \
  --secret-id "${SECRET_NAME}" \
  >/dev/null 2>&1; then

  # シークレットが存在する場合は値を更新
  aws secretsmanager put-secret-value \
    --secret-id "${SECRET_NAME}" \
    --secret-string "${SECRET_VALUE}" \
    >/dev/null

  echo "[Secrets Manager] Secret updated: ${SECRET_NAME}"
else
  # シークレットが存在しない場合は新規作成
  aws secretsmanager create-secret \
    --name "${SECRET_NAME}" \
    --secret-string "${SECRET_VALUE}" \
    >/dev/null

  echo "[Secrets Manager] Secret created: ${SECRET_NAME}"
fi

echo "[Secrets Manager] Initialization completed."