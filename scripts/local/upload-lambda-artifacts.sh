#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
case "${1:-all}" in api|worker) targets=("$1");; all) targets=(api worker);; *) exit 2;; esac
bucket="$(output file_bucket_name)"
[[ "$bucket" == music-app-local-files ]] || { die 'Unexpected artifact bucket'; exit 1; }
backup="$(mktemp -d "$CACHE/lambda-backup.XXXXXX")"
chmod 700 "$backup"
cp "$TFVARS" "$backup/terraform.tfvars"
for kind in "${targets[@]}"; do
  name="musicflows-$kind-lambda.zip"
  key="_lambda-artifacts/$name"
  path="/app/backend-source/build/distributions/$name"
  hash="$(dc exec -T floci python3 -c 'import sys,zipfile,hashlib,base64,pathlib; p=pathlib.Path(sys.argv[1]); z=zipfile.ZipFile(p); assert z.testzip() is None; print(base64.b64encode(hashlib.sha256(p.read_bytes()).digest()).decode())' "$path")"
  [[ "$hash" =~ ^[A-Za-z0-9+/]{43}=$ ]] || exit 1
  if aws_test s3api head-object --bucket "$bucket" --key "$key" > /dev/null 2>"$backup/head-$kind.log"; then
    aws_test s3 cp "s3://$bucket/$key" - > "$backup/$name"
  elif ! grep -Eq '404|Not Found|NoSuchKey' "$backup/head-$kind.log"; then
    die 'Cannot verify old ZIP; refusing overwrite'; exit 1
  fi
  aws_test s3 cp "$path" "s3://$bucket/$key"
  actual="$(aws_test s3 cp "s3://$bucket/$key" - | dc exec -T floci python3 -c 'import sys,hashlib,base64; print(base64.b64encode(hashlib.sha256(sys.stdin.buffer.read()).digest()).decode())')"
  [[ "$actual" == "$hash" ]] || { die 'Uploaded ZIP checksum mismatch'; exit 1; }
  set_var "${kind}_zip_hash" "\"$hash\""
done
log "Backup: $backup. Run Terraform plan/apply next."
