#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
failed=0
check() { local label="$1"; shift; if "$@" >/dev/null; then printf '[OK] %s\n' "$label"; else printf '[FAIL] %s\n' "$label"; failed=1; fi; }
dc --profile worker-local ps -a
check 'PostgreSQL readiness' dc exec -T postgres pg_isready -U app_user -d music_app
check PostgreSQL dc exec -T postgres psql -U app_user -d music_app -v ON_ERROR_STOP=1 -c 'SELECT 1'
check Floci aws_test s3 ls
check S3 aws_test s3api head-bucket --bucket music-app-local-files
check 'Frontend bucket' aws_test s3api head-bucket --bucket music-app-local-frontend
check SQS aws_test sqs get-queue-url --queue-name music-app-local-music-jobs
check DLQ aws_test sqs get-queue-url --queue-name music-app-local-music-jobs-dlq
check 'API Lambda' aws_test lambda get-function --function-name music-app-local-api-handler
check 'Worker Lambda' aws_test lambda get-function --function-name music-app-local-music-job-worker
if mode="$(output worker_execution_mode)" && state="$(mapping_state)" && { [[ "$mode" == lambda && "$state" == Enabled ]] && require_stopped worker-local || [[ "$mode" == local && "$state" == Disabled ]]; }; then
  printf '[OK] Worker mode: %s (%s)\n' "$mode" "$state"
else printf '[FAIL] Worker mode\n'; failed=1; fi
if running backend; then check Backend curl --fail --silent --show-error --max-time 30 http://localhost:8081/api/health; else rc=$?; if [[ "$rc" == 1 ]]; then echo '[SKIP] Backend not started'; else echo '[FAIL] Backend status'; failed=1; fi; fi
if api="$(output runtime_api_url)" && [[ "$api" == http://localhost:4567/* ]]; then check 'API Gateway' curl --fail --silent --show-error --max-time 60 "$api/api/health"; else echo '[FAIL] API URL'; failed=1; fi
check 'Runtime Config' dc exec -T floci python3 /app/scripts/check-frontend-config.py /app/export/frontend-config/local-config.json --stage local
if running frontend; then check Vite curl --fail --silent --show-error --max-time 30 http://localhost:5174/; else rc=$?; if [[ "$rc" == 1 ]]; then echo '[SKIP] Vite not started'; else echo '[FAIL] Vite status'; failed=1; fi; fi
if host="$(dist_host)"; then
  check CloudFront curl --fail --silent --show-error --max-time 30 "http://$host:4567/"
  check 'CloudFront config' curl --fail --silent --show-error --max-time 30 "http://$host:4567/config/local-config.json"
  printf 'CloudFront: http://%s:4567\n' "$host"
else failed=1; fi
exit "$failed"
