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

# AWS CLI を使って SSM パラメータを取得する関数
get_ssm_parameter() {
  aws ssm get-parameter \
    --name "$1" \
    --query Parameter.Value \
    --output text
}

put_ssm_parameter() {
  aws ssm put-parameter \
    --name "$1" \
    --type String \
    --value "$2" \
    --overwrite \
    >/dev/null
}
