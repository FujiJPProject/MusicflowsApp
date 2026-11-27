#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
case "${1:-}" in
  frontend)
    prepare_dirs
    dc stop frontend
    dc build frontend
    dc run --rm --no-deps -T frontend npm ci
    dc run --rm --no-deps -T frontend npm run lint
    dc run --rm --no-deps -T frontend npm run build
    test -f "$ROOT/frontend/dist/index.html"
    ;;
  backend)
    require_existing
    prepare_dirs
    dc stop backend
    dc build backend
    dc up -d --no-deps --no-recreate --wait postgres
    dc run --rm --no-deps -T backend ./gradlew classes test --no-daemon
    ;;
  lambda)
    prepare_dirs
    rm -f "$CACHE/lambda-build.ok"
    dc stop backend
    dc build backend
    dc run --rm --no-deps -T backend ./gradlew clean buildLambdaZips --no-daemon
    test -s "$ROOT/backend/build/distributions/musicflows-api-lambda.zip"
    test -s "$ROOT/backend/build/distributions/musicflows-worker-lambda.zip"
    (cd "$ROOT/backend/build/distributions" && sha256sum musicflows-api-lambda.zip musicflows-worker-lambda.zip) > "$CACHE/lambda-build.ok"
    ;;
  terraform)
    dc --profile tools pull terraform
    run_local terraform sync
    run_local terraform init
    run_local terraform validate
    ;;
  all)
    for target in frontend backend lambda terraform; do run_local build "$target"; done
    ;;
  *) die 'Usage: build.sh frontend|backend|lambda|terraform|all'; exit 2 ;;
esac
