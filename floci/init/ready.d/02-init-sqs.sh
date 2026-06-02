#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"

QUEUE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-music-jobs"

echo "[SQS] Initialization started."

# SQS キュー作成
QUEUE_URL="$(aws sqs create-queue \
  --queue-name "${QUEUE_NAME}" \
  --query QueueUrl \
  --output text)"

echo "[SQS] Queue prepared: ${QUEUE_NAME}"
echo "[SQS] Queue URL: ${QUEUE_URL}"
echo "[SQS] Initialization completed."