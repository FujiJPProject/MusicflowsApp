#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"

API_FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-api-handler"
WORKER_FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-music-job-worker"

ROLE_ARN="arn:aws:iam::000000000000:role/lambda-role"

WORK_DIR="/tmp/music-app-lambda"
API_DIR="${WORK_DIR}/api-handler"
WORKER_DIR="${WORK_DIR}/music-job-worker"
API_ZIP="${WORK_DIR}/api-handler.zip"
WORKER_ZIP="${WORK_DIR}/music-job-worker.zip"

echo "[Lambda] Initialization started."

# ワークディレクトリの準備
rm -rf "${WORK_DIR}"
mkdir -p "${API_DIR}" "${WORKER_DIR}"

# 仮の Lambda ハンドラーコードを作成 (後で本格的なコードに置き換える予定)
cat > "${API_DIR}/index.mjs" <<'EOF'
export const handler = async (event) => {
  const path = event?.path ?? event?.rawPath ?? "";

  if (path === "/api/health") {
    return {
      statusCode: 200,
      headers: {
        "Content-Type": "text/plain",
        "Access-Control-Allow-Origin": "http://localhost:5173"
      },
      body: "OK"
    };
  }

  return {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "http://localhost:5173"
    },
    body: JSON.stringify({
      message: "Temporary Lambda handler is running.",
      path
    })
  };
};
EOF

# 仮の Lambda ハンドラーコードを作成)
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

# Lambda 関数用の ZIP ファイルを作成
python3 - <<EOF
import zipfile

with zipfile.ZipFile("${API_ZIP}", "w", zipfile.ZIP_DEFLATED) as archive:
    archive.write("${API_DIR}/index.mjs", "index.mjs")

with zipfile.ZipFile("${WORKER_ZIP}", "w", zipfile.ZIP_DEFLATED) as archive:
    archive.write("${WORKER_DIR}/index.mjs", "index.mjs")
EOF

# Lambda 関数の作成または更新
create_or_update_function() {
  FUNCTION_NAME="$1"
  ZIP_PATH="$2"

  if aws lambda get-function \
    --function-name "${FUNCTION_NAME}" \
    >/dev/null 2>&1; then

    aws lambda update-function-code \
      --function-name "${FUNCTION_NAME}" \
      --zip-file "fileb://${ZIP_PATH}" \
      >/dev/null

    echo "[Lambda] Function code updated: ${FUNCTION_NAME}"
  else
    aws lambda create-function \
      --function-name "${FUNCTION_NAME}" \
      --runtime nodejs22.x \
      --role "${ROLE_ARN}" \
      --handler index.handler \
      --zip-file "fileb://${ZIP_PATH}" \
      --timeout 30 \
      --memory-size 256 \
      >/dev/null

    echo "[Lambda] Function created: ${FUNCTION_NAME}"
  fi
}

# API ハンドラーとワーカーの Lambda 関数を作成または更新
create_or_update_function "${API_FUNCTION_NAME}" "${API_ZIP}"
create_or_update_function "${WORKER_FUNCTION_NAME}" "${WORKER_ZIP}"

echo "[Lambda] Initialization completed."