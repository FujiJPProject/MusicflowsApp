#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

# Lambda 関数のコードを格納する一時ディレクトリとファイルのパスを定義
WORK_DIR="${LAMBDA_WORK_DIR:-/tmp/music-app-lambda}"
API_DIR="${WORK_DIR}/api-handler"
WORKER_DIR="${WORK_DIR}/music-job-worker"
API_ZIP="${WORK_DIR}/api-handler.zip"
WORKER_ZIP="${WORK_DIR}/music-job-worker.zip"

log "Lambda" "Initialization started."

# 以前の作業領域を削除
rm -rf "${WORK_DIR}"
mkdir -p "${API_DIR}" "${WORKER_DIR}"

# API Gateway と Lambda の疎通確認を目的とした仮実装
# React の開発サーバーから API を呼び出せるように、CORS ヘッダーも含める。
cat > "${API_DIR}/index.mjs" <<EOF
export const handler = async (event) => {
  const path = event?.path ?? event?.rawPath ?? "";

  if (path === "/api/health") {
    return {
      statusCode: 200,
      headers: {
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": "${FRONTEND_ORIGIN}"
      },
      body: "OK"
    };
  }

  return {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "${FRONTEND_ORIGIN}"
    },
    body: JSON.stringify({
      message: "Temporary Lambda handler is running.",
      path
    })
  };
};
EOF

# Worker Lambda の仮実装
cat > "${WORKER_DIR}/index.mjs" <<'EOF'
export const handler = async (event) => {
  console.log("Received music job messages:", JSON.stringify(event));

  for (const record of event.Records ?? []) {
    console.log("Processing music job:", record.body);
  }

  return {
    batchItemFailures: []
  };
};
EOF

# Python の zipfile を使って、Lambda アップロード用 ZIP を作成
python3 - "${API_DIR}" "${WORKER_DIR}" "${API_ZIP}" "${WORKER_ZIP}" <<'PY'
import sys
import zipfile

api_dir, worker_dir, api_zip, worker_zip = sys.argv[1:]

with zipfile.ZipFile(api_zip, "w", zipfile.ZIP_DEFLATED) as archive:
    archive.write(f"{api_dir}/index.mjs", "index.mjs")

with zipfile.ZipFile(worker_zip, "w", zipfile.ZIP_DEFLATED) as archive:
    archive.write(f"{worker_dir}/index.mjs", "index.mjs")
PY

# Lambda 関数の作成または更新
create_or_update_function() {
  function_name="$1"
  zip_path="$2"

  # すでに Lambda 関数が存在するか確認し、存在する場合はコードを更新、存在しない場合は新規作成
  if aws_local lambda get-function --function-name "${function_name}" >/dev/null 2>&1; then
    aws_local lambda update-function-code \
      --function-name "${function_name}" \
      --zip-file "fileb://${zip_path}" \
      >/dev/null
    log "Lambda" "Function code updated: ${function_name}"
  else
    aws_local lambda create-function \
      --function-name "${function_name}" \
      --runtime nodejs22.x \
      --role "${LAMBDA_ROLE_ARN}" \
      --handler index.handler \
      --zip-file "fileb://${zip_path}" \
      --timeout 30 \
      --memory-size 256 \
      >/dev/null
    log "Lambda" "Function created: ${function_name}"
  fi
}

# API Gateway と Lambda の接続は、API Gateway のリソースとメソッドの設定で行うため、ここでは Lambda 関数の作成・更新のみを行う。
create_or_update_function "${API_FUNCTION_NAME}" "${API_ZIP}"
create_or_update_function "${WORKER_FUNCTION_NAME}" "${WORKER_ZIP}"

log "Lambda" "Initialization completed."
