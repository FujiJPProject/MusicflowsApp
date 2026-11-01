# Preserve the local worker as an exclusive alternative to Lambda polling.
resource "aws_lambda_event_source_mapping" "worker" {
  event_source_arn = var.job_queue_arn
  function_name = aws_lambda_function.worker.arn
  batch_size = 1
  function_response_types = ["ReportBatchItemFailures"]
  enabled = var.worker_execution_mode == "lambda"
}
