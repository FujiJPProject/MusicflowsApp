locals {
  api_function_name = "${local.prefix}-api-handler"
  worker_function_name = "${local.prefix}-music-job-worker"
  cognito_issuer_uri = "${var.floci_internal_url}/${aws_cognito_user_pool.users.id}"
  cognito_jwks_uri = "${local.cognito_issuer_uri}/.well-known/jwks.json"
}
resource "aws_lambda_function" "api" {
  function_name = local.api_function_name
  role = var.api_role_arn
  runtime = "java25"
  handler = "com.jws.musicflows.lambda.ApiGatewayLambdaHandler"
  s3_bucket = var.file_bucket_name
  s3_key = "_lambda-artifacts/musicflows-api-lambda.zip"
  source_code_hash = var.api_zip_hash
  timeout = 60
  memory_size = 1024
  publish = true
  dynamic "snap_start" {
    for_each = var.enable_snapstart ? [1] : []
    content {
      apply_on = "PublishedVersions"
    }
  }
  environment {
    variables = {
      SPRING_PROFILES_ACTIVE = "lambda"
      TEST_APIS_ENABLED = "true"
      APP_RUNTIME_TARGET = "floci"
      APP_AWS_REGION = var.aws_region
      AWS_ENDPOINT_URL = var.floci_internal_url
      SQS_QUEUE_NAME = var.job_queue_name
      FILE_BUCKET = var.file_bucket_name
      FRONTEND_ORIGIN = var.frontend_origin
      FRONTEND_ALLOWED_ORIGINS = var.frontend_allowed_origins
      COGNITO_ISSUER_URI = local.cognito_issuer_uri
      COGNITO_JWK_SET_URI = local.cognito_jwks_uri
      COGNITO_APP_CLIENT_ID = aws_cognito_user_pool_client.web.id
      DB_SECRET_NAME = aws_secretsmanager_secret.db.name
    }
  }
}
resource "aws_lambda_alias" "api" {
  name = "live"
  function_name = aws_lambda_function.api.function_name
  function_version = aws_lambda_function.api.version
}
resource "aws_lambda_function" "worker" {
  function_name = local.worker_function_name
  role = var.worker_role_arn
  runtime = "java25"
  handler = "org.springframework.cloud.function.adapter.aws.FunctionInvoker::handleRequest"
  s3_bucket = var.file_bucket_name
  s3_key = "_lambda-artifacts/musicflows-worker-lambda.zip"
  source_code_hash = var.worker_zip_hash
  timeout = 30
  memory_size = 512
  environment {
    variables = {
      SPRING_PROFILES_ACTIVE = "worker-lambda"
      MAIN_CLASS = "com.jws.musicworker.WorkerFunctionApplication"
      spring_cloud_function_definition = "musicJobWorker"
      APP_RUNTIME_TARGET = "floci"
      APP_AWS_REGION = var.aws_region
      AWS_ENDPOINT_URL = var.floci_internal_url
      FILE_BUCKET = var.file_bucket_name
    }
  }
}
