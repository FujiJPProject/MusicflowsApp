#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
dc --profile worker-local stop
log 'Containers stopped; volumes and Terraform state retained.'
