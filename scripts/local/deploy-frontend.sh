#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
run_local export-frontend-config
bucket="$(output frontend_bucket_name)"
id="$(output frontend_distribution_id)"
dc exec -T floci sh /app/scripts/deploy-frontend-local.sh "$bucket" "$id"
printf 'CloudFront: http://%s:4567\n' "$(dist_host)"
