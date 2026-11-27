#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
mode="${1:-status}"
if [[ "$mode" == status ]]; then
  current_mode="$(output worker_execution_mode)"
  state="$(mapping_state)"
  printf 'Terraform mode: %s\nMapping: %s\n' "$current_mode" "$state"
  dc --profile worker-local ps worker-local
  exit 0
fi
[[ "$mode" == local || "$mode" == lambda ]] || exit 2
confirm '切替中は新規ジョブを登録しないでください。続行しますか？' || exit 1
# Stop local worker before any mapping change; never run both consumers.
dc --profile worker-local stop worker-local
require_stopped worker-local
current_mode="$(output worker_execution_mode)"
if [[ "$current_mode" != "$mode" ]]; then
  set_var worker_execution_mode "\"$mode\""
  run_local terraform plan
  run_local terraform apply
fi
if [[ "$mode" == local ]]; then
  wait_mapping Disabled
  assert_drained
else
  wait_mapping Enabled
fi
runtime_env
# Recreate a running direct Backend only when its environment changed.
if running backend; then dc up -d --no-deps backend; else rc=$?; [[ "$rc" == 1 ]] || exit "$rc"; fi
run_local deploy-frontend
if [[ "$mode" == local ]]; then
  wait_mapping Disabled
  dc --profile worker-local up -d --no-deps worker-local
fi
