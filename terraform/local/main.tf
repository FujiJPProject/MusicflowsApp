module "job_messaging" {
  source = "../modules/job-infrastructure"

  file_bucket_name = var.file_bucket_name
  job_queue_name   = var.job_queue_name
  dlq_name         = var.dlq_name

  max_receive_count          = 5
  enable_redrive_allow_policy = false
}

output "file_bucket_name" {
  value = module.job_messaging.file_bucket_name
}

output "job_queue_name" {
  value = module.job_messaging.job_queue_name
}

output "job_queue_url" {
  value = module.job_messaging.job_queue_url
}

output "job_queue_arn" {
  value = module.job_messaging.job_queue_arn
}

output "dlq_url" {
  value = module.job_messaging.dlq_url
}

output "dlq_arn" {
  value = module.job_messaging.dlq_arn
}

# Opt-in so the Issue #35 S3/SQS-only flow remains available.
module "runtime" {
  count = var.enable_runtime_infrastructure ? 1 : 0
  source = "../modules/runtime-infrastructure"
  project_name = "music-app"
  environment = "local"
  aws_region = var.aws_region
  file_bucket_name = module.job_messaging.file_bucket_name
  job_queue_name = module.job_messaging.job_queue_name
  job_queue_arn = module.job_messaging.job_queue_arn
  api_role_arn = aws_iam_role.api[0].arn
  worker_role_arn = aws_iam_role.worker[0].arn
  frontend_origin = var.frontend_origin
  frontend_allowed_origins = var.enable_frontend_delivery ? join(",", [
    var.frontend_origin,
    "http://${lower(module.frontend_delivery[0].distribution_id)}.cloudfront.localhost.floci.io:${var.floci_viewer_port}"
  ]) : var.frontend_origin
  worker_execution_mode = var.worker_execution_mode
  enable_snapstart = var.enable_snapstart
  api_zip_hash = var.api_zip_hash
  worker_zip_hash = var.worker_zip_hash
  floci_internal_url = var.floci_endpoint_url
  floci_host_url = var.floci_host_url
  depends_on = [
    aws_iam_role_policy.api_jobs,
    aws_iam_role_policy.worker_jobs,
    aws_iam_role_policy.api_secret,
  ]
}
output "runtime_api_url" { value = try(module.runtime[0].api_url, null) }
output "runtime_mapping_uuid" { value = try(module.runtime[0].mapping_uuid, null) }
output "runtime_user_pool_id" { value = try(module.runtime[0].user_pool_id, null) }
output "runtime_client_id" { value = try(module.runtime[0].client_id, null) }

# Frontendはジョブ結果・Lambda ZIP用S3とは別のバケットに配置。
# 既存Issue #35/#36では初期値falseのため一切変更されない。
module "frontend_delivery" {
  count = var.enable_frontend_delivery ? 1 : 0

  source               = "../modules/frontend-delivery"
  name_prefix          = "music-app-local"
  frontend_bucket_name = var.frontend_bucket_name
}

output "frontend_bucket_name" {
  value = try(module.frontend_delivery[0].bucket_name, null)
}

output "frontend_distribution_id" {
  value = try(module.frontend_delivery[0].distribution_id, null)
}

output "frontend_distribution_domain_name" {
  value = try(module.frontend_delivery[0].distribution_domain_name, null)
}
