# 実AWSの開発環境も同じモジュールを再利用。Issue35では適用しない。
module "job_messaging" {
  source = "../modules/job-messaging"

  file_bucket_name = var.file_bucket_name
  job_queue_name   = var.job_queue_name
  dlq_name         = var.dlq_name

  max_receive_count          = 5
  enable_redrive_allow_policy = true
}

output "file_bucket_name" {
  value = module.job_messaging.file_bucket_name
}

output "job_queue_url" {
  value = module.job_messaging.job_queue_url
}

output "dlq_url" {
  value = module.job_messaging.dlq_url
}

output "api_iam_policy_json" {
  value = module.job_messaging.api_iam_policy_json
}

output "worker_iam_policy_json" {
  value = module.job_messaging.worker_iam_policy_json
}

output "artifact_deployer_iam_policy_json" {
  value = module.job_messaging.artifact_deployer_iam_policy_json
}
