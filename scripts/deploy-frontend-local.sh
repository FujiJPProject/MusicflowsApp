#!/usr/bin/env bash
# Floci専用。実AWSに対してデプロイしない。
set -euo pipefail

cd "$(dirname "$0")/.."
TEST_PROJECT="${TEST_PROJECT:-music-app-terraform-test}"
TEST_COMPOSE="docker-compose.terraform-test.yml"
CONFIG_SOURCE=".docker-cache/terraform-test/frontend-config/local-config.json"
CONFIG_DEST="frontend/dist/config/local-config.json"
BUCKET="music-app-local-frontend"

if [[ ! -f "$CONFIG_SOURCE" ]]; then
  echo "Floci生成済みのRuntime Configがありません: $CONFIG_SOURCE" >&2
  exit 1
fi
if [[ ! -f frontend/dist/index.html || ! -d frontend/dist/assets ]]; then
  echo "先にViteの本番ビルドを行ってください: frontend/dist/" >&2
  exit 1
fi

# 不完全なConfigやAWS向けConfigをローカルへ誤配信しない。
python3 scripts/check-frontend-config.py "$CONFIG_SOURCE" --stage local
mkdir -p frontend/dist/config
cp "$CONFIG_SOURCE" "$CONFIG_DEST"
python3 scripts/check-frontend-config.py "$CONFIG_DEST" --stage local

tf() {
  docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" \
    --profile tools run --rm --no-deps terraform \
    -chdir=terraform/local "$@"
}
aws_local() {
  docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" \
    exec -T floci aws --endpoint-url http://localhost:4566 \
    --region ap-northeast-1 "$@"
}

# Stateとアップロード先の一致を検証。既存ジョブ用バケットへの誤配備を防ぐ。
actual_bucket="$(tf output -raw frontend_bucket_name)"
dist_id="$(tf output -raw frontend_distribution_id)"
if [[ "$actual_bucket" != "$BUCKET" || -z "$dist_id" || "$dist_id" == "null" ]]; then
  echo "Terraform Outputの配信先が期待値と一致しません" >&2
  exit 1
fi

aws_local s3api head-bucket --bucket "$BUCKET" >/dev/null
aws_local cloudfront get-distribution --id "$dist_id" >/dev/null

# Viteハッシュ付きアセットは不変URLとする。
aws_local s3 sync /app/frontend-dist/assets/ "s3://${BUCKET}/assets/" \
  --cache-control "public,max-age=31536000,immutable"

# Viteのpublic配下も含めてコピー。HTMLとConfigは独立に更新する。
aws_local s3 sync /app/frontend-dist/ "s3://${BUCKET}/" \
  --exclude "index.html" --exclude "assets/*" --exclude "config/*" \
  --cache-control "public,max-age=3600"

aws_local s3 cp "/app/frontend-dist/config/local-config.json" \
  "s3://${BUCKET}/config/local-config.json" \
  --content-type "application/json" --cache-control "no-store,max-age=0"

# HTMLを最後にアップロードすることで存在しないJSを参照させない。
aws_local s3 cp /app/frontend-dist/index.html "s3://${BUCKET}/index.html" \
  --content-type "text/html" --cache-control "no-cache,max-age=0,must-revalidate"

# FlociではInvalidation APIの検証のみ。実キャッシュは再現されない。
aws_local cloudfront create-invalidation --distribution-id "$dist_id" \
  --paths "/" "/index.html" "/config/local-config.json"
echo "Flociへの配信完了。Distribution ID: $dist_id"
