#!/bin/sh
set -eu

# ============================================================
# 共通変数
# 環境変数で上書き可能な値と、命名規則から導出する値を集約する。
# ============================================================

# --------------------------基本設定---------------------------------
# プロジェクト名
PROJECT_NAME="${PROJECT_NAME:-music-app}" 
# 実行環境名
ENVIRONMENT="${ENVIRONMENT:-local}"
# 利用リージョン 
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
# AWSアカウントID (ローカル環境ではダミー値)
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-000000000000}"
# --------------------------基本設定---------------------------------

# --------------------------Floci の接続先設定---------------------------------
AWS_EDGE_HOST_URL="${AWS_EDGE_HOST_URL:-http://localhost:4566}"
AWS_EDGE_INTERNAL_URL="${AWS_EDGE_INTERNAL_URL:-http://floci:4566}"
STAGE_NAME="${STAGE_NAME:-local}"
FRONTEND_ORIGIN="${FRONTEND_ORIGIN:-http://localhost:5173}"
# --------------------------Floci の接続先設定---------------------------------

# --------------------------Parameter Store の共通プレフィックス---------------------------------
# 環境ごとにパラメータをグルーピングするためのプレフィックス
PARAMETER_PREFIX="/${PROJECT_NAME}/${ENVIRONMENT}"

# --------------------------S3・SQS・Secrets Manager・Cognito の名称定義---------------------------------

FRONTEND_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-frontend" # React 配信用ファイル
FILE_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-files" # 楽曲・画像・プロジェクトデータ
QUEUE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-music-jobs" # 楽曲変換ジョブのキュー
SECRET_NAME="${PROJECT_NAME}/${ENVIRONMENT}/db" # DB接続情報

USER_POOL_NAME="${PROJECT_NAME}-${ENVIRONMENT}-users" # ユーザー情報と認証管理
APP_CLIENT_NAME="${PROJECT_NAME}-${ENVIRONMENT}-web-client" # React が認証処理で使用
# --------------------------S3・SQS・Secrets Manager・Cognito の名称定義---------------------------------





API_FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-api-handler"
WORKER_FUNCTION_NAME="${PROJECT_NAME}-${ENVIRONMENT}-music-job-worker"
REST_API_NAME="${PROJECT_NAME}-${ENVIRONMENT}-api"
AUTHORIZER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-cognito-authorizer"

LAMBDA_ROLE_ARN="${LAMBDA_ROLE_ARN:-arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-role}"
FRONTEND_CONFIG_OUTPUT_DIR="${FRONTEND_CONFIG_OUTPUT_DIR:-/app/export/frontend-config}"


# ============================================================
# 共通関数
# ここでは、複数の初期化スクリプトで利用する関数を定義する。
# ============================================================

# ログ出力用の関数
log() {
  component="$1"
  shift
  printf '[%s] %s\n' "${component}" "$*"
}

# AWS CLI のコマンド結果が空または "None" の場合に真を返す関数
is_missing_aws_value() {
  [ -z "$1" ] || [ "$1" = "None" ]
}

# AWS CLI をローカルエンドポイントに対して実行するための関数
# 1. 実 AWS に誤って向く事故を防げる
# 2. API Gateway URL のような http://... 文字列を安全に SSM へ保存できる
aws_local() {
  AWS_CLI_FOLLOW_URLPARAM=false \
  aws --endpoint-url "${AWS_EDGE_HOST_URL}" \
      --region "${AWS_REGION}" \
      "$@"
}

# AWS CLI を使って SSM パラメータを取得する関数
get_ssm_parameter() {
  aws_local ssm get-parameter \
    --name "$1" \
    --query Parameter.Value \
    --output text
}

put_ssm_parameter() {
  name="$1"
  value="$2"

# AWS CLI の put-parameter コマンドは、コマンドライン引数で直接値を渡すと、URL エンコードされてしまう。
# 例えば、http://localhost:4566 のような文字列を渡すと、http%3A%2F%2Flocalhost%3A4566 のように保存されてしまう。
#これを防ぐために、Python の json モジュールを使って、JSON 形式でパラメータを渡す方法を取る。
  json_payload="$(python3 - "${name}" "${value}" <<'PY'
import json
import sys

name = sys.argv[1]
value = sys.argv[2]

print(json.dumps({
    "Name": name,
    "Type": "String",
    "Value": value,
    "Overwrite": True
}))
PY
)"

  aws_local ssm put-parameter \
    --cli-input-json "${json_payload}" \
    >/dev/null
}

