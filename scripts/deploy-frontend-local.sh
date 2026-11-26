#!/bin/sh
# Flociコンテナ内で実行する。TerraformのOutputは引数で受け取る。
# /app/frontend-dist は読み取り専用。ホストのPython/AWS CLI/Dockerには依存しない。
set -eu

BUCKET="music-app-local-frontend"
DIST_DIR="/app/frontend-dist"
CONFIG_SOURCE="/app/export/frontend-config/local-config.json"
VALIDATOR="$(dirname "$0")/check-frontend-config.py"

if [ "$#" -ne 2 ]; then
  echo "Usage: sh deploy-frontend-local.sh <frontend_bucket_name> <distribution_id>" >&2
  exit 1
fi

actual_bucket="$1"
dist_id="$2"
case "$dist_id" in
  ""|null|None|*[!a-zA-Z0-9]*)
    echo "Terraform OutputのDistribution IDが不正です" >&2
    exit 1
    ;;
esac
if [ "$actual_bucket" != "$BUCKET" ]; then
  echo "Terraform Outputの配信先が期待値と一致しません" >&2
  exit 1
fi

if [ ! -f "$CONFIG_SOURCE" ] || [ ! -f "$VALIDATOR" ]; then
  echo "Runtime Configまたは設定検証スクリプトがありません" >&2
  exit 1
fi
if [ ! -f "$DIST_DIR/index.html" ] || [ ! -d "$DIST_DIR/assets" ]; then
  echo "先にViteの本番ビルドを行ってください: $DIST_DIR" >&2
  exit 1
fi

# 生成済みConfigを一時ファイルへコピーして検証。検証済みの同一内容を配信する。
# 読み取り専用のdistやRuntime Configの生成元には書き込まない。
umask 077
config_snapshot="$(mktemp)"
trap 'rm -f "$config_snapshot"' EXIT
cp "$CONFIG_SOURCE" "$config_snapshot"
python3 "$VALIDATOR" "$config_snapshot" --stage local

aws_local() {
  aws --endpoint-url http://localhost:4566 --region ap-northeast-1 "$@"
}

aws_local s3api head-bucket --bucket "$BUCKET" >/dev/null
aws_local cloudfront get-distribution --id "$dist_id" >/dev/null

# Viteハッシュ付きアセットは不変URLとする。
aws_local s3 sync "$DIST_DIR/assets/" "s3://${BUCKET}/assets/" \
  --cache-control "public,max-age=31536000,immutable"

# ビルドに含まれ得る旧Configは配信しない。生成済みConfigだけを別途配信する。
aws_local s3 sync "$DIST_DIR/" "s3://${BUCKET}/" \
  --exclude "index.html" --exclude "assets/*" --exclude "config/*" \
  --cache-control "public,max-age=3600"

aws_local s3 cp "$config_snapshot" \
  "s3://${BUCKET}/config/local-config.json" \
  --content-type "application/json" --cache-control "no-store,max-age=0"

# HTMLは最後に配置する。既存ハッシュ付きアセットは削除しない。
aws_local s3 cp "$DIST_DIR/index.html" "s3://${BUCKET}/index.html" \
  --content-type "text/html" --cache-control "no-cache,max-age=0,must-revalidate"

# FlociではInvalidation APIの検証のみ。実エッジキャッシュは再現されない。
aws_local cloudfront create-invalidation --distribution-id "$dist_id" \
  --paths "/" "/index.html" "/config/local-config.json"
echo "Flociへの配信完了。Distribution ID: $dist_id"
