#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
mode="${1:-status}"
if [[ "$mode" == status ]]; then
  printf 'Terraform mode: %s\nMapping: %s\n' "$(output worker_execution_mode)" "$(mapping_state)"
  dc --profile worker-local ps worker-local
  exit 0
fi
[[ "$mode" == local || "$mode" == lambda ]] || exit 2
confirm '切替中は新規ジョブを登録しないでください。続行しますか？' || exit 1
# Stop local worker before any mapping change; never run both consumers.
dc --profile worker-local stop worker-local
if running worker-local; then die 'Local worker still running'; exit 1; fi
if [[ "$(output worker_execution_mode)" != "$mode" ]]; then
  set_var worker_execution_mode "\"$mode\""
  run_local terraform plan
  run_local terraform apply
fi
if [[ "$mode" == local ]]; then
  wait_mapping Disabled
  assert_drained
  dc --profile worker-local up -d --no-deps worker-local
else
  wait_mapping Enabled
fi
run_local export-frontend-config
run_local deploy-frontend
