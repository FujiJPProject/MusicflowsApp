#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "SQS" "Initialization started."

# SQS キュー作成 
QUEUE_URL="$(aws sqs create-queue \
  --queue-name "${QUEUE_NAME}" \
  --query QueueUrl \
  --output text)"

log "SQS" "Queue prepared: ${QUEUE_NAME}"
log "SQS" "Queue URL: ${QUEUE_URL}"
log "SQS" "Initialization completed."
