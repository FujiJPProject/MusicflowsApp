#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "S3" "Initialization started."
# S3 作成スクリプト関数
create_bucket() {
  bucket_name="$1"

  # AWS CLI の head-bucket コマンドでバケットの存在を確認し、存在しない場合に作成する。
  if aws_local s3api head-bucket --bucket "${bucket_name}" >/dev/null 2>&1; then
    log "S3" "Bucket already exists: ${bucket_name}"
    return
  fi

  # S3 バケットの作成。リージョンによってコマンドが異なるため、条件分岐で対応する。
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws_local s3api create-bucket \
      --bucket "${bucket_name}" \
      --region "${AWS_REGION}" \
      >/dev/null
  else
    aws_local s3api create-bucket \
      --bucket "${bucket_name}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" \
      >/dev/null
  fi

  log "S3" "Bucket created: ${bucket_name}"
}

# S3 バケットの作成
create_bucket "${FILE_BUCKET}"

log "S3" "Initialization completed."
