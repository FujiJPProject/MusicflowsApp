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
export API_BASE_URL
export USER_POOL_ID
export APP_CLIENT_ID
export AWS_REGION
export WORKER_EXECUTION_MODE

python3 - "${OUTPUT_FILE}" <<'PY'
import json
import os
import sys
import tempfile
from pathlib import Path

output_file = Path(sys.argv[1])

required = [
    "API_BASE_URL",
    "USER_POOL_ID",
    "APP_CLIENT_ID",
    "AWS_REGION",
    "WORKER_EXECUTION_MODE",
]

# 必須の環境変数が設定されているか確認する
for name in required:
    value = os.environ.get(name, "").strip()

    if not value or value == "None":
        raise ValueError(f"Required frontend config is missing: {name}")

# フロントエンドで使用する設定を辞書として作成
config = {
    "deploymentStage": "local",
    "apiBaseUrl": os.environ["API_BASE_URL"],
    "directApiBaseUrl": "http://localhost:8080",
    "cognitoUserPoolId": os.environ["USER_POOL_ID"],
    "cognitoClientId": os.environ["APP_CLIENT_ID"],
    "awsRegion": os.environ["AWS_REGION"],
    "cognitoEndpointUrl": "http://localhost:4566",
    "workerExecutionMode": os.environ[
        "WORKER_EXECUTION_MODE"
    ],
    "testPagesEnabled": True,
}

temporary_path = None

try:
    # 一時ファイルを作成して設定を出力する
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=output_file.parent,
        prefix=".local-config-",
        suffix=".tmp",
        delete=False,
    ) as file:

        # 一時ファイルのパスを保持しておく
        temporary_path = Path(file.name)
        json.dump(config, file, indent=2)
        file.write("\n")

    # Runtime Configはフロントエンドが読み取る公開設定。
    # 一時ファイルのデフォルト権限600を644に変更する。
    os.chmod(temporary_path, 0o644)

    # 生成が完了したファイルを正式な設定ファイルへ置き換える。
    os.replace(temporary_path, output_file)

except Exception:
    if temporary_path is not None:
        temporary_path.unlink(missing_ok=True)
    raise
PY

log "Frontend Config" "Worker execution mode: ${WORKER_EXECUTION_MODE}"

log "Frontend Config" "File created: ${OUTPUT_FILE}"

log "Frontend Config" "Export completed."