#!/bin/sh
set -eu

PROJECT_NAME="${PROJECT_NAME:-music-app}"
ENVIRONMENT="${ENVIRONMENT:-local}"

QUEUE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-music-jobs"
WORKER_FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-music-job-worker"

echo "[Lambda Event Source] Initialization started."

# SQS キューの URL を取得
QUEUE_URL="$(aws sqs get-queue-url \
  --queue-name "${QUEUE_NAME}" \
  --query QueueUrl \
  --output text)"

# SQS キューの ARN を取得
QUEUE_ARN="$(aws sqs get-queue-attributes \
  --queue-url "${QUEUE_URL}" \
  --attribute-names QueueArn \
  --query Attributes.QueueArn \
  --output text)"

# Lambda 関数と SQS キューをイベントソースマッピングで接続
MAPPING_ID="$(aws lambda list-event-source-mappings \
  --function-name "${WORKER_FUNCTION_NAME}" \
  --event-source-arn "${QUEUE_ARN}" \
  --query "EventSourceMappings[0].UUID" \
  --output text)"

# イベントソースマッピングが存在しない場合は作成
if [ "${MAPPING_ID}" = "None" ] || [ -z "${MAPPING_ID}" ]; then
  aws lambda create-event-source-mapping \
    --function-name "${WORKER_FUNCTION_NAME}" \
    --event-source-arn "${QUEUE_ARN}" \
    --batch-size 10 \
    >/dev/null

  echo "[Lambda Event Source] Mapping created."
else
  echo "[Lambda Event Source] Mapping already exists."
fi

echo "[Lambda Event Source] Initialization completed."