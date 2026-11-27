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
if [[ "$current" != "$FLOCI_CORS_ALLOWED_ORIGINS" ]] || ! dc exec -T floci test -f /app/scripts/check-frontend-config.py || ! dc exec -T floci test -d /app/backend-source; then
  confirm 'FlociのCORS・マウント設定反映のため再作成しますか？' || exit 1
  require_stopped worker-local
  assert_drained
  dc up -d --no-deps --force-recreate floci
  wait_floci
fi
case "$mode" in
  worker-local)
    [[ "$WORKER_EXECUTION_MODE" == local && "$(mapping_state)" == Disabled ]] || { die 'Run worker-mode.sh local first.'; exit 1; }
    if running worker-local; then :; else rc=$?; [[ "$rc" == 1 ]] || exit "$rc"; assert_drained; fi
    dc --profile worker-local up -d --no-deps worker-local
    dc up -d --no-deps backend
    ;;
  lambda|all)
    [[ "$WORKER_EXECUTION_MODE" == lambda && "$(mapping_state)" == Enabled ]] || { die 'Run worker-mode.sh lambda first.'; exit 1; }
    require_stopped worker-local
    run_local export-frontend-config
    dc up -d --no-deps frontend
    if [[ "$mode" == all ]]; then dc up -d --no-deps backend; fi
    ;;
  frontend) run_local export-frontend-config; dc up -d --no-deps frontend ;;
  backend) dc up -d --no-deps backend ;;
esac
dc --profile worker-local ps
