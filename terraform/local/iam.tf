# Local Floci roles. AWS IAM management belongs to MusicflowInfra, not here.
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "api" {
  count = var.enable_runtime_infrastructure ? 1 : 0
  name = "music-app-local-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role" "worker" {
  count = var.enable_runtime_infrastructure ? 1 : 0
  name = "music-app-local-worker-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}
resource "aws_iam_role_policy" "api_jobs" {
  count = var.enable_runtime_infrastructure ? 1 : 0
  name = "music-app-local-api-jobs"
  role = aws_iam_role.api[0].id
  policy = module.job_messaging.api_iam_policy_json
}
resource "aws_iam_role_policy" "worker_jobs" {
  count = var.enable_runtime_infrastructure ? 1 : 0
  name = "music-app-local-worker-jobs"
  role = aws_iam_role.worker[0].id
  policy = module.job_messaging.worker_iam_policy_json
}
# This policy does NOT reference module.runtime, avoiding a module dependency cycle.
data "aws_iam_policy_document" "api_secret" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:000000000000:secret:music-app/local/db-*"]
  }
}
resource "aws_iam_role_policy" "api_secret" {
  count = var.enable_runtime_infrastructure ? 1 : 0
  name = "music-app-local-api-secret"
  role = aws_iam_role.api[0].id
  policy = data.aws_iam_policy_document.api_secret.json
}
