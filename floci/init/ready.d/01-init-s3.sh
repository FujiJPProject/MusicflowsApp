#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

FRONTEND_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-frontend"
FILE_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-files"

echo "[S3] Initialization started."

# S3 作成スクリプト
create_bucket() {
  BUCKET_NAME="$1"

  if aws s3api head-bucket --bucket "${BUCKET_NAME}" >/dev/null 2>&1; then
    echo "[S3] Bucket already exists: ${BUCKET_NAME}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" \
      >/dev/null

    echo "[S3] Bucket created: ${BUCKET_NAME}"
  fi
}

# フロントエンド用とファイル保存用のバケットを作成
create_bucket "${FRONTEND_BUCKET}"
create_bucket "${FILE_BUCKET}"

echo "[S3] Initialization completed."