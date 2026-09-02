#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "Lambda Event Source" "Initialization started."

#  キューのURLを取得する。
QUEUE_URL="$(
  aws_local sqs get-queue-url \
    --queue-name "${QUEUE_NAME}" \
    --query QueueUrl \
    --output text
)"

# キューのARNを取得する。
QUEUE_ARN="$(
  aws_local sqs get-queue-attributes \
    --queue-url "${QUEUE_URL}" \
    --attribute-names QueueArn \
    --query Attributes.QueueArn \
    --output text
)"

# LambdaのEvent Source Mappingを取得する。
MAPPING_ID="$(
  aws_local lambda list-event-source-mappings \
    --function-name "${WORKER_FUNCTION_NAME}" \
    --event-source-arn "${QUEUE_ARN}" \
    --query "EventSourceMappings[0].UUID" \
    --output text
)"

#  mappingが存在しない場合は、AWS CLIの戻り値が "None" になるので、空文字列に変換する。
if is_missing_aws_value "${MAPPING_ID}"; then

  # ----------------------------------------------------------
  # 新規作成
  # ----------------------------------------------------------

  aws_local lambda create-event-source-mapping \
    --function-name "${WORKER_FUNCTION_NAME}" \
    --event-source-arn "${QUEUE_ARN}" \
    --batch-size 1 \
    --function-response-types ReportBatchItemFailures \
    >/dev/null

  log "Lambda Event Source" "Mapping created."

else

  # ----------------------------------------------------------
  # 既存Mappingについても設定を収束させる
  # ----------------------------------------------------------

  aws_local lambda update-event-source-mapping \
    --uuid "${MAPPING_ID}" \
    --batch-size 1 \
    --function-response-types ReportBatchItemFailures \
    --enabled \
    >/dev/null

  log "Lambda Event Source" "Mapping updated."

fi


log "Lambda Event Source" "Initialization completed."