#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "Lambda Event Source" "Initialization started."

# ------------------------------------------------------------
# Worker実行モードの妥当性確認
# ------------------------------------------------------------

case "${WORKER_EXECUTION_MODE}" in
  local|lambda)
    ;;
  *)
    log \
      "Lambda Event Source" \
      "Invalid WORKER_EXECUTION_MODE: ${WORKER_EXECUTION_MODE}"

    log \
      "Lambda Event Source" \
      "Allowed values are: local, lambda"

    exit 1
    ;;
esac


# ------------------------------------------------------------
# SQS Queue URL取得
# ------------------------------------------------------------

QUEUE_URL="$(
  aws_local sqs get-queue-url \
    --queue-name "${QUEUE_NAME}" \
    --query QueueUrl \
    --output text
)"


# ------------------------------------------------------------
# SQS Queue ARN取得
# ------------------------------------------------------------

QUEUE_ARN="$(
  aws_local sqs get-queue-attributes \
    --queue-url "${QUEUE_URL}" \
    --attribute-names QueueArn \
    --query Attributes.QueueArn \
    --output text
)"


# ------------------------------------------------------------
# 現在のEvent Source Mapping取得
# ------------------------------------------------------------

MAPPING_ID="$(
  aws_local lambda list-event-source-mappings \
    --function-name "${WORKER_FUNCTION_NAME}" \
    --event-source-arn "${QUEUE_ARN}" \
    --query "EventSourceMappings[0].UUID" \
    --output text
)"

if is_missing_aws_value "${MAPPING_ID}"; then
  MAPPING_ID=""
fi


# ------------------------------------------------------------
# Event Source Mappingが期待状態になるまで待機する。
#
# Floci/AWSともにupdate直後は、
# Enabling / Disablingの中間状態になる可能性があるため、
# 即時判定せず状態が収束するまで確認する。
# ------------------------------------------------------------

wait_mapping_state() {
  mapping_id="$1"
  expected_state="$2"

  attempt=1

  while [ "${attempt}" -le 30 ]; do

    current_state="$(
      aws_local lambda get-event-source-mapping \
        --uuid "${mapping_id}" \
        --query State \
        --output text
    )"

    if [ "${current_state}" = "${expected_state}" ]; then
      log \
        "Lambda Event Source" \
        "Mapping state: ${current_state}"

      return 0
    fi

    log \
      "Lambda Event Source" \
      "Waiting for mapping state: current=${current_state}, expected=${expected_state}"

    sleep 1

    attempt=$((attempt + 1))
  done

  log \
    "Lambda Event Source" \
    "Mapping did not reach expected state: ${expected_state}"

  return 1
}


# ------------------------------------------------------------
# Local Workerモード
#
# worker-localがSQSを直接pollするため、
# Lambda側のEvent Source Mappingを必ず停止する。
# ------------------------------------------------------------

if [ "${WORKER_EXECUTION_MODE}" = "local" ]; then

  if [ -z "${MAPPING_ID}" ]; then

    log \
      "Lambda Event Source" \
      "Mapping does not exist. No Lambda polling is configured."

  else

    aws_local lambda update-event-source-mapping \
      --uuid "${MAPPING_ID}" \
      --no-enabled \
      >/dev/null

    wait_mapping_state \
      "${MAPPING_ID}" \
      "Disabled"

    log \
      "Lambda Event Source" \
      "Mapping disabled for local worker mode."

  fi

  log \
    "Lambda Event Source" \
    "Worker execution mode: local"

  log \
    "Lambda Event Source" \
    "Initialization completed."

  exit 0
fi


# ------------------------------------------------------------
# Lambda Workerモード
#
# Event Source Mappingを作成または有効化し、
# Worker LambdaだけがSQSを処理する。
# ------------------------------------------------------------

if [ -z "${MAPPING_ID}" ]; then

  MAPPING_ID="$(
    aws_local lambda create-event-source-mapping \
      --function-name "${WORKER_FUNCTION_NAME}" \
      --event-source-arn "${QUEUE_ARN}" \
      --batch-size 1 \
      --function-response-types ReportBatchItemFailures \
      --enabled \
      --query UUID \
      --output text
  )"

  wait_mapping_state \
    "${MAPPING_ID}" \
    "Enabled"

  log \
    "Lambda Event Source" \
    "Mapping created and enabled."

else

  aws_local lambda update-event-source-mapping \
    --uuid "${MAPPING_ID}" \
    --batch-size 1 \
    --function-response-types ReportBatchItemFailures \
    --enabled \
    >/dev/null

  wait_mapping_state \
    "${MAPPING_ID}" \
    "Enabled"

  log \
    "Lambda Event Source" \
    "Mapping updated and enabled."

fi


log \
  "Lambda Event Source" \
  "Worker execution mode: lambda"

log \
  "Lambda Event Source" \
  "Initialization completed."