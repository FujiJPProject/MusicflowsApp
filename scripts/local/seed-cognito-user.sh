#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
prepare
require_existing
pool="$(output runtime_user_pool_id)"
read -r -p '開発用ユーザー（メールアドレス）: ' username
[[ -n "$username" ]] || exit 1
lookup_error="$(mktemp)"
trap 'rm -f "$lookup_error"' EXIT
if status="$(aws_test cognito-idp admin-get-user --user-pool-id "$pool" --username "$username" --query UserStatus --output text 2>"$lookup_error")"; then
  [[ "$status" == CONFIRMED ]] || { die "Existing user is $status; recover explicitly, no password reset."; exit 1; }
  log 'Existing confirmed user kept.'; exit 0
fi
if ! grep -q 'UserNotFoundException' "$lookup_error"; then
  die 'Cognito lookup failed; refusing to create a user.'; exit 1
fi
read -rs -p '開発用ユーザーパスワード: ' password; printf '\n' >&2
[[ -n "$password" ]] || exit 1
printf '%s' "$password" | dc exec -T floci python3 -c '
import json, sys, tempfile, subprocess, os
pool,user=sys.argv[1:]; pwd=sys.stdin.read()
base=["aws","--endpoint-url","http://localhost:4566","--region","ap-northeast-1","cognito-idp"]
def call(action,data):
    with tempfile.NamedTemporaryFile(mode="w",delete=False) as f:
        path=f.name; json.dump(data,f)
    try:
        subprocess.run(base+[action,"--cli-input-json","file://"+path],check=True,stdout=subprocess.DEVNULL)
    finally: os.unlink(path)
call("admin-create-user",dict(UserPoolId=pool,Username=user,TemporaryPassword=pwd,MessageAction="SUPPRESS",UserAttributes=[dict(Name="email",Value=user),dict(Name="email_verified",Value="true")]))
call("admin-set-user-password",dict(UserPoolId=pool,Username=user,Password=pwd,Permanent=True))
' "$pool" "$username"
unset password
[[ "$(aws_test cognito-idp admin-get-user --user-pool-id "$pool" --username "$username" --query UserStatus --output text)" == CONFIRMED ]]
log 'Cognito user confirmed.'
