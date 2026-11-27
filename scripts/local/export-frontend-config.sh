#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
runtime_env
api="$(output runtime_api_url)"
[[ "$api" == http://localhost:4567/* ]] || { die 'Unexpected API URL'; exit 1; }
dc exec -T -e EXPORT_FRONTEND_CONFIG_FORCE=1 -e FLOCI_INIT_PHASE=runtime \
  -e "WORKER_EXECUTION_MODE=$WORKER_EXECUTION_MODE" -e "TEST_APIS_ENABLED=$TEST_APIS_ENABLED" \
  floci sh /app/manual-init/09-export-frontend-config.sh
dc exec -T floci python3 /app/scripts/check-frontend-config.py /app/export/frontend-config/local-config.json --stage local
