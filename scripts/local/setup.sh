#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
case "$(state_kind)" in
  existing) log 'Existing state and volumes: use start.sh or resume the failed step; no bootstrap.'; exit 1;;
  partial) die 'State/Volume mismatch. See troubleshooting. No automatic recovery.'; exit 1;;
  new) ;;
esac
confirm '新規環境を構築しますか？旧Shell環境のデータは自動移行しません。' || exit 1
mkdir -p "$TFDIR" "$CACHE/frontend-config" "$CACHE/secrets" "$CACHE/backend-gradle" "$CACHE/worker-gradle" "$CACHE/worker-build" "$ROOT/backend/build/distributions" "$ROOT/frontend/dist"
umask 077
[[ ! -e "$TFVARS" ]] || { die 'Existing tfvars: inspect before setup'; exit 1; }
cp "$ROOT/terraform/local/terraform.tfvars.example" "$TFVARS"
set_var enable_runtime_infrastructure true
set_var enable_frontend_delivery true
set_var frontend_origin '"http://localhost:5174"'
set_var floci_host_url '"http://localhost:4567"'
set_var worker_execution_mode '"lambda"'
run_local terraform sync
start_infra
run_local build lambda
run_local build frontend
run_local terraform init
run_local terraform validate
export MUSICFLOWS_NEW_SETUP=yes
run_local terraform bootstrap
unset MUSICFLOWS_NEW_SETUP
run_local put-db-secret
run_local upload-lambda-artifacts all
run_local terraform plan
run_local terraform apply
run_local seed-cognito-user
run_local deploy-frontend
run_local start all
run_local check
