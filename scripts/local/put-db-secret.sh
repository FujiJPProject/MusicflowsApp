#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
# Verify password against PostgreSQL using stdin, not CLI arguments.
printf '%s\n' "$TEST_DB_PASSWORD" | dc exec -T postgres sh -c 'IFS= read -r PGPASSWORD; export PGPASSWORD; psql -h 127.0.0.1 -U app_user -d music_app -v ON_ERROR_STOP=1 -c "SELECT 1"' >/dev/null
aws_test secretsmanager describe-secret --secret-id music-app/local/db >/dev/null
lookup_error="$(mktemp)"
trap 'rm -f "$lookup_error"' EXIT
if aws_test secretsmanager get-secret-value --secret-id music-app/local/db >/dev/null 2>"$lookup_error"; then
  confirm '既存DB Secretの実値を更新しますか？' || exit 1
elif ! grep -q 'ResourceNotFoundException' "$lookup_error"; then
  die 'Secret lookup failed; refusing to overwrite.'; exit 1
fi
printf '%s' "$TEST_DB_PASSWORD" | dc exec -T floci python3 -c '
import json, sys, tempfile, subprocess, os
password=sys.stdin.read()
with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
    name=f.name
    json.dump(dict(host="postgres",port=5432,dbname="music_app",username="app_user",password=password),f)
try:
    subprocess.run(["aws","--endpoint-url","http://localhost:4566","--region","ap-northeast-1","secretsmanager","put-secret-value","--secret-id","music-app/local/db","--secret-string","file://"+name],check=True,stdout=subprocess.DEVNULL)
finally:
    os.unlink(name)
'
log 'DB Secret registered.'
