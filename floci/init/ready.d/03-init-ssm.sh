#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "${SCRIPT_DIR}/00-common.sh"

log "SSM" "Initialization started."

# SSM パラメータの設定
put_ssm_parameter "${PARAMETER_PREFIX}/app-name" "${PROJECT_NAME}"
put_ssm_parameter "${PARAMETER_PREFIX}/file-bucket-name" "${FILE_BUCKET}"
put_ssm_parameter "${PARAMETER_PREFIX}/music-job-queue-name" "${QUEUE_NAME}"

log "SSM" "Parameter prepared: ${PARAMETER_PREFIX}/app-name"
log "SSM" "Parameter prepared: ${PARAMETER_PREFIX}/file-bucket-name"
log "SSM" "Parameter prepared: ${PARAMETER_PREFIX}/music-job-queue-name"
log "SSM" "Initialization completed."
