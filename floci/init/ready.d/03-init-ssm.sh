#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"

FILE_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-files"
QUEUE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-music-jobs"
PARAMETER_PREFIX="/${PROJECT_NAME}/${ENVIRONMENT}"

echo "[SSM] Initialization started."

# SSM パラメータストアにアプリケーション設定を保存
aws ssm put-parameter \
  --name "${PARAMETER_PREFIX}/app-name" \
  --type String \
  --value "${PROJECT_NAME}" \
  --overwrite \
  >/dev/null

# SSM パラメータストアにバケット名とキュー名を保存
aws ssm put-parameter \
  --name "${PARAMETER_PREFIX}/file-bucket-name" \
  --type String \
  --value "${FILE_BUCKET}" \
  --overwrite \
  >/dev/null

# SSM パラメータストアにキュー名を保存
aws ssm put-parameter \
  --name "${PARAMETER_PREFIX}/music-job-queue-name" \
  --type String \
  --value "${QUEUE_NAME}" \
  --overwrite \
  >/dev/null

echo "[SSM] Parameter prepared: ${PARAMETER_PREFIX}/app-name"
echo "[SSM] Parameter prepared: ${PARAMETER_PREFIX}/file-bucket-name"
echo "[SSM] Parameter prepared: ${PARAMETER_PREFIX}/music-job-queue-name"
echo "[SSM] Initialization completed."