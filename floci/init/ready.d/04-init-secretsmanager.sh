#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

DB_HOST="${DB_HOST:-postgres}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-music_app}"
DB_USERNAME="${DB_USERNAME:-app_user}"
DB_PASSWORD="${DB_PASSWORD:-app_password}"

# DB接続情報を JSON 形式でシークレットに保存するための値を生成
# ここでは、Python を使って環境変数から JSON 文字列を生成している。
# これにより、Secrets Manager に保存するシークレットの値が一貫した形式で管理される。
SECRET_VALUE="$(DB_HOST="${DB_HOST}" DB_PORT="${DB_PORT}" DB_NAME="${DB_NAME}" \
  DB_USERNAME="${DB_USERNAME}" DB_PASSWORD="${DB_PASSWORD}" python3 - <<'PY'
import json
import os

print(json.dumps({
    "host": os.environ["DB_HOST"],
    "port": os.environ["DB_PORT"],
    "dbname": os.environ["DB_NAME"],
    "username": os.environ["DB_USERNAME"],
    "password": os.environ["DB_PASSWORD"],
}))
PY
)"

log "Secrets Manager" "Initialization started."

# シークレットが既に存在するか確認
if aws secretsmanager describe-secret \
  --secret-id "${SECRET_NAME}" \
  >/dev/null 2>&1; then

  # シークレットが存在する場合は値を更新
  aws secretsmanager put-secret-value \
    --secret-id "${SECRET_NAME}" \
    --secret-string "${SECRET_VALUE}" \
    >/dev/null

  log "Secrets Manager" "Secret updated: ${SECRET_NAME}"
else
  # シークレットが存在しない場合は新規作成
  aws secretsmanager create-secret \
    --name "${SECRET_NAME}" \
    --secret-string "${SECRET_VALUE}" \
    >/dev/null

  log "Secrets Manager" "Secret created: ${SECRET_NAME}"
fi

log "Secrets Manager" "Initialization completed."