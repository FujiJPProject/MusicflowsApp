#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "SQS" "Initialization started."


# ------------------------------------------------------------
# Queue取得
# ------------------------------------------------------------

QUEUE_URL="$(
  aws_local sqs get-queue-url \
    --queue-name "${QUEUE_NAME}" \
    --query QueueUrl \
    --output text \
    2>/dev/null || true
)"


# ------------------------------------------------------------
# Queueが存在しない場合だけ作成
# ------------------------------------------------------------

if is_missing_aws_value "${QUEUE_URL}"; then

  QUEUE_URL="$(
    aws_local sqs create-queue \
      --queue-name "${QUEUE_NAME}" \
      --attributes VisibilityTimeout=180 \
      --query QueueUrl \
      --output text
  )"

  log "SQS" "Queue created: ${QUEUE_NAME}"

else

  log "SQS" "Queue already exists: ${QUEUE_NAME}"

fi


# ------------------------------------------------------------
# 既存Queueについても設定値を収束させる
#
# Worker Lambda timeout = 30秒
# Visibility Timeout = 30 × 6 = 180秒
# ------------------------------------------------------------

aws_local sqs set-queue-attributes \
  --queue-url "${QUEUE_URL}" \
  --attributes VisibilityTimeout=180 \
  >/dev/null


log "SQS" "Queue URL: ${QUEUE_URL}"
log "SQS" "Visibility timeout: 180 seconds"
log "SQS" "Initialization completed."