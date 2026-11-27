#!/usr/bin/env bash
# Source only: do not change the caller's shell options.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT=music-app-terraform-test
CACHE="$ROOT/.docker-cache/terraform-test"
TFDIR="$CACHE/terraform/local"
TFVARS="$TFDIR/terraform.tfvars"
export HOST_UID="$(id -u)" HOST_GID="$(id -g)"
die() { printf '[ERROR] %s\n' "$*" >&2; return 1; }
log() { printf '[local] %s\n' "$*" >&2; }
confirm() {
  local answer
  [[ -t 0 ]] || { die "Interactive approval required: $*"; return 1; }
  read -r -p "$* [yes/no]: " answer
  [[ "$answer" == yes ]]
}
require_password() {
  if [[ -z "${TEST_DB_PASSWORD:-}" ]]; then
    [[ -t 0 ]] || { die 'Set TEST_DB_PASSWORD securely first.'; return 1; }
    read -rs -p '開発用DBパスワード（既存DBは元の値）: ' TEST_DB_PASSWORD
    printf '\n' >&2
  fi
  [[ -n "$TEST_DB_PASSWORD" ]] || { die 'Empty password'; return 1; }
  export TEST_DB_PASSWORD
}
dc() { docker compose --project-directory "$ROOT" -p "$PROJECT" -f "$ROOT/docker-compose.yml" "$@"; }
aws_test() { dc exec -T floci aws --endpoint-url http://localhost:4566 --region ap-northeast-1 "$@"; }
tf_test() { dc --profile tools run --rm --no-deps -T terraform -chdir=terraform/local "$@"; }
run_local() { bash "$ROOT/scripts/local/$1.sh" "${@:2}"; }
lock_local() {
  mkdir -p "$CACHE"
  if [[ "${MUSICFLOWS_LOCK_HELD:-}" == "$CACHE" && -e /proc/$$/fd/9 ]]; then return 0; fi
  exec 9>"$CACHE/.operation.lock"
  flock -n 9 || { die 'Another local operation is running.'; return 1; }
  export MUSICFLOWS_LOCK_HELD="$CACHE"
}
prepare() {
  command -v docker >/dev/null
  docker info >/dev/null
  docker compose version >/dev/null
  require_password
  lock_local
}
running() { [[ -n "$(dc --profile worker-local ps --status running -q "$1")" ]]; }
state_kind() {
  local pg=0 fl=0 st=0
  if docker volume inspect "${PROJECT}_terraform_test_postgres_data" >/dev/null 2>&1; then pg=1; fi
  if docker volume inspect "${PROJECT}_terraform_test_floci_data" >/dev/null 2>&1; then fl=1; fi
  if [[ -s "$TFDIR/terraform.tfstate" ]]; then st=1; fi
  case "$pg$fl$st" in 000) echo new;; 111) echo existing;; *) echo partial;; esac
}
require_existing() {
  [[ "$(state_kind)" == existing ]] || die 'State/Volume mismatch or new environment. See setup/troubleshooting; do not delete data.'
}
wait_floci() {
  local n
  for n in $(seq 1 60); do
    if aws_test s3 ls >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  die 'Floci not ready; inspect dc logs floci.'
}
start_infra() {
  dc up -d --no-deps --no-recreate --wait postgres
  dc up -d --no-deps --no-recreate floci
  wait_floci
}
output() {
  local v
  v="$(tf_test output -raw "$1")" || return 1
  [[ -n "$v" && "$v" != null && "$v" != None ]] || { die "Missing Terraform output: $1"; return 1; }
  printf '%s\n' "$v"
}
dist_host() {
  local id
  id="$(output frontend_distribution_id)" || return 1
  [[ "$id" =~ ^[a-zA-Z0-9]+$ ]] || { die 'Invalid distribution id'; return 1; }
  printf '%s.cloudfront.localhost.floci.io' "$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
}
runtime_env() {
  local host
  host="$(dist_host)" || return 1
  export FLOCI_CORS_ALLOWED_ORIGINS="http://localhost:5174,http://$host:4567"
  export FRONTEND_ALLOWED_ORIGINS="$FLOCI_CORS_ALLOWED_ORIGINS"
  WORKER_EXECUTION_MODE="$(output worker_execution_mode)" || return 1
  TEST_APIS_ENABLED="$(output test_apis_enabled)" || return 1
  [[ "$WORKER_EXECUTION_MODE" == local || "$WORKER_EXECUTION_MODE" == lambda ]] || return 1
  [[ "$TEST_APIS_ENABLED" == true || "$TEST_APIS_ENABLED" == false ]] || return 1
  export WORKER_EXECUTION_MODE TEST_APIS_ENABLED
}
set_var() {
  local key="$1" value="$2" tmp
  [[ "$key" =~ ^[a-z_]+$ && "$value" != *$'\n'* ]] || return 1
  [[ -f "$TFVARS" ]] || return 1
  tmp="$(mktemp "$TFDIR/.tfvars.XXXXXX")"
  if ! awk -v k="$key" -v v="$value" '
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {n++; if(n==1) print k " = " v; next}
    {print}
    END {if(n==0) print k " = " v; if(n>1) exit 1}
  ' "$TFVARS" > "$tmp"; then rm -f "$tmp"; return 1; fi
  mv "$tmp" "$TFVARS"
  rm -f "$TFDIR/runtime.tfplan"
}
mapping_state() {
  local uuid
  uuid="$(output runtime_mapping_uuid)" || return 1
  [[ "$uuid" =~ ^[a-fA-F0-9-]+$ ]] || return 1
  aws_test lambda get-event-source-mapping --uuid "$uuid" --query State --output text
}
wait_mapping() {
  local n state
  for n in $(seq 1 60); do
    state="$(mapping_state)" || return 1
    [[ "$state" == "$1" ]] && return 0
    sleep 2
  done
  die "Mapping failed to reach $1"
}
assert_drained() {
  local url count
  url="$(output job_queue_url)" || return 1
  count="$(aws_test sqs get-queue-attributes --queue-url "$url" --attribute-names ApproximateNumberOfMessagesNotVisible --query Attributes.ApproximateNumberOfMessagesNotVisible --output text)" || return 1
  [[ "$count" == 0 ]] || { die 'In-flight jobs exist; stop submissions and wait.'; return 1; }
  confirm '新規ジョブ停止・実行中ジョブ終了を確認しましたか？'
}
