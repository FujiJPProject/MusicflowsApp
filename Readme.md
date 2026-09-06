# MusicflowsApp概要

[コンテナ構成に関して](./doc/コンテナ構成/Readme.md)

## 起動確認(コンソール)

```shell
docker compose run --rm --no-deps backend \
  ./gradlew clean buildLambdaZips --no-daemon
```

### 1. zipを確認する
```shell
cd ~/music-app

ls -lh backend/build/distributions/
```

```text
musicflows-api-lambda.zip
musicflows-worker-lambda.zip
```

### 2. コンテナを起動する
```shell
export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"

docker compose down
docker compose pull floci
docker compose up -d --build
```

状態の確認
```shell
docker compose ps
docker compose logs --no-color --tail=300 floci
```

### 3. AWS CLI用関数を定義する

Flociコンテナ内のAWS CLIを使用するため

```shell
awslocal() {
  docker compose exec -T floci aws \
    --endpoint-url http://localhost:4566 \
    --region ap-northeast-1 \
    "$@"
}
```

### 4. Lambdaを確認
```shell
awslocal lambda list-functions \
  --query 'Functions[].{Name:FunctionName,Runtime:Runtime,Handler:Handler,State:State}' \
  --output table
```

期待値
```text
music-app-local-api-handler
music-app-local-music-job-worker
```

### 5. 5. API GatewayのIDと統合先を確認

API IDの取得
```shell
API_ID="$(
  awslocal apigateway get-rest-apis \
    --query "items[?name=='music-app-local-api'].id | [0]" \
    --output text
)"

echo "API_ID=${API_ID}"
```

リソースを確認。/{proxy+} が存在するか必要
```shell
awslocal apigateway get-resources \
  --rest-api-id "${API_ID}" \
  --output table
```

```shell
PROXY_RESOURCE_ID="$(
  awslocal apigateway get-resources \
    --rest-api-id "${API_ID}" \
    --query "items[?path=='/{proxy+}'].id | [0]" \
    --output text
)"

echo "PROXY_RESOURCE_ID=${PROXY_RESOURCE_ID}"
```

統合先を確認
```shell
awslocal apigateway get-integration \
  --rest-api-id "${API_ID}" \
  --resource-id "${PROXY_RESOURCE_ID}" \
  --http-method ANY \
  --query '{Type:type,HttpMethod:httpMethod,Uri:uri}' \
  --output table
```

### 6. 6. 正しいAPI URLを取得

```shell
API_BASE_URL="$(
  awslocal ssm get-parameter \
    --name /music-app/local/api-base-url-host \
    --query 'Parameter.Value' \
    --output text
)"

echo "${API_BASE_URL}"
```

### 7. /api/health を確認
```shell
curl -sS -i "${API_BASE_URL}/api/health"
```

期待値
```
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"OK"}
```

### 8. Cognitoアクセストークンを取得する
```shell
USER_POOL_ID="$(
  awslocal ssm get-parameter \
    --name /music-app/local/cognito-user-pool-id \
    --query 'Parameter.Value' \
    --output text
)"

APP_CLIENT_ID="$(
  awslocal ssm get-parameter \
    --name /music-app/local/cognito-app-client-id \
    --query 'Parameter.Value' \
    --output text
)"

echo "USER_POOL_ID=${USER_POOL_ID}"
echo "APP_CLIENT_ID=${APP_CLIENT_ID}"
```


```shell
ACCESS_TOKEN="$(
  awslocal cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id "${APP_CLIENT_ID}" \
    --auth-parameters \
      'USERNAME=local-user@example.com,PASSWORD=LocalPass123!' \
    --query 'AuthenticationResult.AccessToken' \
    --output text
)"

test -n "${ACCESS_TOKEN}" && test "${ACCESS_TOKEN}" != "None"
echo "Access token acquired"
```

### 9. /api/tests GETを確認

```shell
curl -sS -i "${API_BASE_URL}/api/tests" -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

期待値
```text
HTTP/1.1 200 OK
```

### 10.  /api/tests POSTを確認
```shell
curl -sS -i \
  -X POST \
  "${API_BASE_URL}/api/tests" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"name":"Floci API Gateway test"}'
```

期待値
```text
HTTP/1.1 201 Created
Location: /api/tests/<ID>
```

### lambda側のエラーの確認

```shell
docker ps -a \
  --filter label=io.floci.resource-id=music-app-local-api-handler \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

## 11. Work flow側のLambdaのissuer設定を確認する

```shell
awslocal lambda get-function-configuration \
  --function-name music-app-local-api-handler \
  --query 'Environment.Variables.{
    Issuer:COGNITO_ISSUER_URI,
    Jwks:COGNITO_JWK_SET_URI,
    ClientId:COGNITO_APP_CLIENT_ID
  }' \
  --output table
```

```text
Issuer   http://floci:4566/<UserPoolId>
Jwks     http://floci:4566/<UserPoolId>/.well-known/jwks.json
ClientId <APP_CLIENT_IDと同じ値>
```

## 12. SQSとWorker Lambdaの接続を確認する

```shell
QUEUE_NAME="music-app-local-music-jobs"
WORKER_FUNCTION_NAME="music-app-local-music-job-worker"
BUCKET_NAME="music-app-local-files"

QUEUE_URL="$(
  awslocal sqs get-queue-url \
    --queue-name "${QUEUE_NAME}" \
    --query QueueUrl \
    --output text
)"

QUEUE_ARN="$(
  awslocal sqs get-queue-attributes \
    --queue-url "${QUEUE_URL}" \
    --attribute-names QueueArn \
    --query Attributes.QueueArn \
    --output text
)"

echo "QUEUE_URL=${QUEUE_URL}"
echo "QUEUE_ARN=${QUEUE_ARN}"
```

イベントソースマッピングを確認
```shell
awslocal lambda list-event-source-mappings \
  --function-name "${WORKER_FUNCTION_NAME}" \
  --event-source-arn "${QUEUE_ARN}" \
  --query 'EventSourceMappings[].{
    UUID:UUID,
    State:State,
    BatchSize:BatchSize,
    FunctionResponseTypes:FunctionResponseTypes
  }' \
  --output table
```

```text
State                  Enabled
BatchSize              1
```

## 13. APIからジョブを登録

レスポンス保存用の一時ファイルを作成
```shell
CREATE_RESPONSE_FILE="$(mktemp)"
```

ジョブを登録
```shell
CREATE_HTTP_STATUS="$(
  curl -sS \
    -o "${CREATE_RESPONSE_FILE}" \
    -w '%{http_code}' \
    -X POST \
    "${API_BASE_URL}/api/test-jobs" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{"payload":"music flows lambda test"}'
)"

echo "HTTP status: ${CREATE_HTTP_STATUS}"
python3 -m json.tool "${CREATE_RESPONSE_FILE}"
```

```text
HTTP status: 202

{
    "jobId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "status": "QUEUED",
    "resultKey": "worker-results/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json"
}
```

## 14. jobIdとS3キーを取得する
```shell
JOB_ID="$(
  python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1]))["jobId"])' \
    "${CREATE_RESPONSE_FILE}"
)"

RESULT_KEY="$(
  python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1]))["resultKey"])' \
    "${CREATE_RESPONSE_FILE}"
)"

echo "JOB_ID=${JOB_ID}"
echo "RESULT_KEY=${RESULT_KEY}"
```

## 15. API経由で処理完了を待つ

```shell
RESULT_RESPONSE_FILE="$(mktemp)"
RESULT_COMPLETED=false

for attempt in $(seq 1 30); do
  RESULT_HTTP_STATUS="$(
    curl -sS \
      -o "${RESULT_RESPONSE_FILE}" \
      -w '%{http_code}' \
      "${API_BASE_URL}/api/test-jobs/${JOB_ID}/result" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}"
  )"

  echo "確認 ${attempt}/30: HTTP ${RESULT_HTTP_STATUS}"

  if [ "${RESULT_HTTP_STATUS}" = "200" ]; then
    RESULT_COMPLETED=true
    break
  fi

  if [ "${RESULT_HTTP_STATUS}" != "202" ]; then
    echo "想定外のHTTPステータスです"
    python3 -m json.tool "${RESULT_RESPONSE_FILE}" 2>/dev/null \
      || sed -n '1,200p' "${RESULT_RESPONSE_FILE}"
    break
  fi

  sleep 2
done
```

```shell
if [ "${RESULT_COMPLETED}" = "true" ]; then
  echo "ジョブ処理完了"
  python3 -m json.tool "${RESULT_RESPONSE_FILE}"
else
  echo "60秒以内に処理が完了しませんでした"
fi
```

```text
{
    "jobId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "status": "COMPLETED",
    "requestedBy": "Cognitoユーザーのsub",
    "processedPayload": "MUSIC FLOWS LAMBDA TEST",
    "processedAt": "2026-09-..."
}
```

```shell
if [ "${RESULT_COMPLETED}" = "true" ]; then
  echo "ジョブ処理完了"
  python3 -m json.tool "${RESULT_RESPONSE_FILE}"
else
  echo "60秒以内に処理が完了しませんでした"
fi
```

```text
{
    "jobId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "status": "COMPLETED",
    "requestedBy": "Cognitoユーザーのsub",
    "processedPayload": "MUSIC FLOWS LAMBDA TEST",
    "processedAt": "2026-09-..."
}
```

## 16. S3へ直接アクセスして結果を確認する

S3オブジェクトを標準出力経由でWSL側のファイルへ保存
```shell
S3_RESULT_FILE="$(mktemp)"

awslocal s3 cp \
  "s3://${BUCKET_NAME}/${RESULT_KEY}" \
  - \
  --only-show-errors \
  > "${S3_RESULT_FILE}"
```

ファイルが空でないことを確認
```shell
ls -lh "${S3_RESULT_FILE}"
test -s "${S3_RESULT_FILE}" \
  && echo "S3 result downloaded"
```

JSONを表示
```shell
python3 -m json.tool "${S3_RESULT_FILE}"
```


## 17. SQSの残件数を確認する

```shell
awslocal sqs get-queue-attributes \
  --queue-url "${QUEUE_URL}" \
  --attribute-names \
    ApproximateNumberOfMessages \
    ApproximateNumberOfMessagesNotVisible \
  --query Attributes \
  --output table
```

```text
ApproximateNumberOfMessages           0
ApproximateNumberOfMessagesNotVisible 0
```

## 18. Lambdaログを確認する
```shell
docker compose logs --since=10m floci \
  | grep -E "${JOB_ID}|Music job completed|ERROR|Exception"
```

```text
Music job completed:
jobId=<JOB_ID>
bucket=music-app-local-files
key=worker-results/<JOB_ID>.json
```
