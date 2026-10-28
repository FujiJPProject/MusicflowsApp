output "file_bucket_name" {
  value = aws_s3_bucket.files.id
}

output "file_bucket_arn" {
  value = aws_s3_bucket.files.arn
}

output "job_queue_name" {
  value = aws_sqs_queue.jobs.name
}

output "job_queue_url" {
  value = aws_sqs_queue.jobs.url
}

output "job_queue_arn" {
  value = aws_sqs_queue.jobs.arn
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "api_iam_policy_json" {
  value = data.aws_iam_policy_document.api.json
}

output "worker_iam_policy_json" {
  value = data.aws_iam_policy_document.worker.json
}

output "artifact_deployer_iam_policy_json" {
  value = data.aws_iam_policy_document.artifact_deployer.json
}
