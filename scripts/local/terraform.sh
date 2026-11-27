#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
cmd="${1:-}"
shift || true
case "$cmd" in
  sync)
    mkdir -p "$CACHE/terraform"
    # Only .tf files are synchronized; never overwrite state, tfvars or lock files.
    while IFS= read -r -d '' f; do
      rel="${f#"$CACHE/terraform/"}"
      if [[ ! -f "$ROOT/terraform/$rel" ]]; then
        confirm "Remove stale Terraform definition $rel?" || exit 1
        rm -- "$f"
      fi
    done < <(find "$CACHE/terraform" -name .terraform -prune -o -type f -name '*.tf' -print0)
    while IFS= read -r -d '' f; do
      rel="${f#"$ROOT/terraform/"}"
      mkdir -p "$CACHE/terraform/$(dirname "$rel")"
      cp -- "$f" "$CACHE/terraform/$rel"
    done < <(find "$ROOT/terraform/local" "$ROOT/terraform/modules" -type f -name '*.tf' -not -path '*/.terraform/*' -print0)
    rm -f "$TFDIR/runtime.tfplan"
    ;;
  init) tf_test init -input=false ;;
  validate) tf_test validate ;;
  output) tf_test output "$@" ;;
  plan)
    require_existing
    rm -f "$TFDIR/runtime.tfplan"
    tf_test plan -input=false -out=runtime.tfplan
    ;;
  apply)
    require_existing
    [[ -f "$TFDIR/runtime.tfplan" ]] || { die 'Run plan first.'; exit 1; }
    if running worker-local; then die 'Stop worker-local before applying a plan.'; exit 1; fi
    tf_test show runtime.tfplan
    tf_test show -json runtime.tfplan | dc exec -T floci python3 -c 'import json,sys; p=json.load(sys.stdin); sys.exit(any("delete" in r["change"]["actions"] for r in p.get("resource_changes",[])))' || { die 'Plan contains deletion/replacement or inspection failed.'; exit 1; }
    confirm '表示されたPlanを適用しますか？' || exit 1
    tf_test apply -input=false runtime.tfplan
    rm -f "$TFDIR/runtime.tfplan"
    ;;
  check)
    require_existing
    rc=0
    tf_test plan -input=false -detailed-exitcode || rc=$?
    printf 'Plan exit code: %s\n' "$rc"
    exit "$rc"
    ;;
  bootstrap)
    [[ "${MUSICFLOWS_NEW_SETUP:-}" == yes && ! -e "$TFDIR/terraform.tfstate" ]] || { die 'Bootstrap is restricted to a fresh setup.'; exit 1; }
    tf_test plan -input=false -target=module.job_messaging -target='module.runtime[0].aws_secretsmanager_secret.db' -out=bootstrap.tfplan
    tf_test show bootstrap.tfplan
    confirm '初回Bootstrap Planを適用しますか？' || exit 1
    tf_test apply -input=false bootstrap.tfplan
    rm -f "$TFDIR/bootstrap.tfplan"
    ;;
  *) die 'Usage: terraform.sh sync|init|validate|plan|apply|check|output|bootstrap'; exit 2 ;;
esac
