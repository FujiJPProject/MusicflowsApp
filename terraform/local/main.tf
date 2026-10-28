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
