#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "Lambda Event Source" "Initialization started."

# SQS キューの URLの取得
QUEUE_URL="$(aws sqs get-queue-url \
  --queue-name "${QUEUE_NAME}" \
  --query QueueUrl \
  --output text)"

# SQS キューの ARN の取得
QUEUE_ARN="$(aws sqs get-queue-attributes \
  --queue-url "${QUEUE_URL}" \
  --attribute-names QueueArn \
  --query Attributes.QueueArn \
  --output text)"

# Lambda 関数と SQS キューのイベントソースマッピングの作成 (存在しない場合)
MAPPING_ID="$(aws lambda list-event-source-mappings \
  --function-name "${WORKER_FUNCTION_NAME}" \
  --event-source-arn "${QUEUE_ARN}" \
  --query "EventSourceMappings[0].UUID" \
  --output text)"

if is_missing_aws_value "${MAPPING_ID}"; then
  aws lambda create-event-source-mapping \
    --function-name "${WORKER_FUNCTION_NAME}" \
    --event-source-arn "${QUEUE_ARN}" \
    --batch-size 10 \
    >/dev/null
  log "Lambda Event Source" "Mapping created."
else
  log "Lambda Event Source" "Mapping already exists."
fi

log "Lambda Event Source" "Initialization completed."
