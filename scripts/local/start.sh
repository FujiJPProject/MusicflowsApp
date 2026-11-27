#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
mode="${1:-all}"
case "$mode" in infrastructure|frontend|backend|worker-local|lambda|all) ;; *) exit 2;; esac
start_infra
[[ "$mode" == infrastructure ]] && exit 0
runtime_env
# Preserve the running Floci container unless its CORS setting needs an explicit change.
current="$(dc exec -T floci printenv FLOCI_SECURITY_EXTRA_CORS_ALLOWED_ORIGINS)"
if [[ "$current" != "$FLOCI_CORS_ALLOWED_ORIGINS" ]]; then
  confirm 'FlociのCORS設定反映のため再作成しますか？' || exit 1
  if running worker-local; then die 'Stop worker-local before recreating Floci'; exit 1; fi
  dc up -d --no-deps floci
  wait_floci
fi
case "$mode" in
  worker-local)
    [[ "$WORKER_EXECUTION_MODE" == local && "$(mapping_state)" == Disabled ]] || { die 'Run worker-mode.sh local first.'; exit 1; }
    if ! running worker-local; then assert_drained; fi
    dc --profile worker-local up -d --no-deps worker-local
    dc up -d --no-deps backend
    ;;
  lambda|all)
    [[ "$WORKER_EXECUTION_MODE" == lambda && "$(mapping_state)" == Enabled ]] || { die 'Run worker-mode.sh lambda first.'; exit 1; }
    if running worker-local; then die 'Local worker unexpectedly running'; exit 1; fi
    run_local export-frontend-config
    dc up -d --no-deps frontend
    if [[ "$mode" == all ]]; then dc up -d --no-deps backend; fi
    ;;
  frontend) run_local export-frontend-config; dc up -d --no-deps frontend ;;
  backend) dc up -d --no-deps backend ;;
esac
dc --profile worker-local ps
